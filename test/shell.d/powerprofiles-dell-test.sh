#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

profile_root="$tmp_dir/platform-profile"
mkdir -p "$tmp_dir/bin" "$tmp_dir/state" "$profile_root/platform-profile-0" "$profile_root/platform-profile-1"

printf '%s\n' "SoC Power Slider" >"$profile_root/platform-profile-0/name"
printf '%s\n' "low-power balanced performance" >"$profile_root/platform-profile-0/choices"
printf '%s\n' "balanced" >"$profile_root/platform-profile-0/profile"
printf '%s\n' "dell-pc" >"$profile_root/platform-profile-1/name"
printf '%s\n' "cool quiet balanced performance" >"$profile_root/platform-profile-1/choices"
printf '%s\n' "quiet" >"$profile_root/platform-profile-1/profile"

cat >"$tmp_dir/bin/powerprofilesctl" <<'EOF'
#!/bin/bash

if [[ $1 == "list" ]]; then
  for profile in performance balanced power-saver; do
    [[ $profile != "performance" || ${NO_PERFORMANCE:-0} == "0" ]] || continue
    if [[ $(<"$POWERPROFILES_OS_STATE") == "$profile" ]]; then
      printf '* %s:\n' "$profile"
    else
      printf '  %s:\n' "$profile"
    fi
  done
elif [[ $1 == "get" ]]; then
  cat "$POWERPROFILES_OS_STATE"
elif [[ $1 == "set" ]]; then
  printf '%s\n' "$2" >>"$POWERPROFILES_LOG"
  if [[ ${POWERPROFILES_NEVER_SETTLE:-0} == "1" && $2 == "power-saver" ]]; then
    printf '%s\n' "balanced" >"$POWERPROFILES_OS_STATE"
  elif [[ ${POWERPROFILES_STEP_DOWN:-0} == "1" && $(<"$POWERPROFILES_OS_STATE") == "performance" && $2 == "power-saver" ]]; then
    printf '%s\n' "balanced" >"$POWERPROFILES_OS_STATE"
  else
    printf '%s\n' "$2" >"$POWERPROFILES_OS_STATE"
  fi
fi
EOF
chmod +x "$tmp_dir/bin/powerprofilesctl"

export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"
export POWERPROFILES_LOG="$tmp_dir/calls"
export POWERPROFILES_OS_STATE="$tmp_dir/os-profile"
export OMARCHY_POWERPROFILES_STATE_DIR="$tmp_dir/state"
export OMARCHY_PLATFORM_PROFILE_ROOT="$profile_root"
printf '%s\n' "power-saver" >"$POWERPROFILES_OS_STATE"

output=$("$ROOT/bin/omarchy-powerprofiles-list")
[[ $output == $'quiet\ncool\nbalanced\nperformance' ]] || fail "Dell power profiles use the intended order"
pass "Dell power profiles use the intended order"

output=$("$ROOT/bin/omarchy-powerprofiles-list" --active-state)
[[ $output == $'quiet\t1\ncool\t0\nbalanced\t0\nperformance\t0' ]] || fail "Dell power profiles report firmware state"
pass "Dell power profiles report combined firmware and OS state"

printf '%s\n' "balanced" >"$POWERPROFILES_OS_STATE"
output=$("$ROOT/bin/omarchy-powerprofiles-list" --active-state)
[[ $output == $'quiet\t0\ncool\t0\nbalanced\t0\nperformance\t0' ]] || fail "mismatched OS and firmware profiles are not reported as active"
pass "Dell power profiles require matching firmware and OS state"
printf '%s\n' "power-saver" >"$POWERPROFILES_OS_STATE"

output=$(NO_PERFORMANCE=1 "$ROOT/bin/omarchy-powerprofiles-list")
[[ $output == $'quiet\ncool\nbalanced' ]] || fail "Dell modes require their mapped OS profile"
pass "Dell modes are limited to available OS profiles"

printf '%s\n' "power-saver" >"$tmp_dir/state/battery"
"$ROOT/bin/omarchy-powerprofiles-set" battery
[[ $(<"$POWERPROFILES_OS_STATE") == "power-saver" ]] || fail "saved OS power-saver keeps its OS profile"
[[ $(<"$profile_root/platform-profile-1/profile") == "quiet" ]] || fail "saved OS power-saver becomes Dell quiet"
pass "existing power-saver preferences map to Dell quiet"

for mapping in "quiet power-saver" "cool power-saver" "balanced balanced" "performance performance"; do
  read -r dell_profile os_profile <<<"$mapping"
  "$ROOT/bin/omarchy-powerprofiles-set" ac "$dell_profile"
  [[ $(tail -n 1 "$POWERPROFILES_LOG") == $os_profile ]] || fail "$dell_profile selects OS $os_profile"
  [[ $(<"$POWERPROFILES_OS_STATE") == $os_profile ]] || fail "$dell_profile updates the OS profile"
  [[ $(<"$profile_root/platform-profile-1/profile") == $dell_profile ]] || fail "$dell_profile selects the Dell firmware profile"
  [[ $(<"$tmp_dir/state/ac") == $dell_profile ]] || fail "$dell_profile is remembered"
  active_profile=$("$ROOT/bin/omarchy-powerprofiles-list" --active-state | awk '$2 == 1 { print $1 }')
  [[ $active_profile == $dell_profile ]] || fail "$dell_profile reports the combined mode as active"
  pass "$dell_profile maps and persists correctly"
done

if "$ROOT/bin/omarchy-powerprofiles-set" ac power-saver 2>/dev/null; then
  fail "Dell profile selection rejects hidden OS profiles"
fi
pass "Dell profile selection rejects hidden OS profiles"

if POWERPROFILES_NEVER_SETTLE=1 "$ROOT/bin/omarchy-powerprofiles-set" ac quiet 2>/dev/null; then
  fail "Dell profile selection reports an OS profile that does not settle"
fi
[[ $(<"$POWERPROFILES_OS_STATE") == "performance" ]] || fail "failed OS profile selection restores the previous OS profile"
[[ $(<"$profile_root/platform-profile-1/profile") == "performance" ]] || fail "failed OS profile selection preserves Dell firmware"
[[ $(<"$tmp_dir/state/ac") == "performance" ]] || fail "failed OS profile selection preserves the preference"
pass "Dell profile selection rolls back an OS profile that does not settle"

call_count=$(wc -l <"$POWERPROFILES_LOG")
POWERPROFILES_STEP_DOWN=1 "$ROOT/bin/omarchy-powerprofiles-set" ac quiet
[[ $(wc -l <"$POWERPROFILES_LOG") == $(( call_count + 2 )) ]] || fail "Dell profile selection waits for the OS profile to settle"
[[ $(<"$POWERPROFILES_OS_STATE") == "power-saver" ]] || fail "stepped OS profile reaches power-saver"
[[ $(<"$profile_root/platform-profile-1/profile") == "quiet" ]] || fail "stepped OS profile reaches Dell quiet"
pass "Dell profile selection converges stepped OS profile changes"

chmod 444 "$profile_root/platform-profile-1/profile"
output=$("$ROOT/bin/omarchy-powerprofiles-list")
[[ $output == $'power-saver\nbalanced\nperformance' ]] || fail "unwritable Dell profiles fall back to OS profiles"
"$ROOT/bin/omarchy-powerprofiles-set" ac power-saver
[[ $(<"$POWERPROFILES_OS_STATE") == "power-saver" ]] || fail "OS profiles remain selectable when Dell firmware is not writable"
[[ $(<"$profile_root/platform-profile-1/profile") == "quiet" ]] || fail "OS fallback does not change Dell firmware"
pass "unwritable Dell profiles preserve the standard OS controls"
