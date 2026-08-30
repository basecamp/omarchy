#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1788060589.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
fixtures="$test_tmp/fixtures"
mkdir -p "$stub_bin" "$fixtures"

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == "-Qo" ]] || exit 98

if [[ ${PACMAN_ERROR_PATH:-} == "$2" ]]; then
  echo "error: package database unavailable" >&2
  exit 2
fi

case ":${PACMAN_OWNED_PATHS:-}:" in
  *:"$2":*)
    echo "$2 is owned by test-package 1-1"
    exit 0
    ;;
esac

echo "error: No package owns $2" >&2
exit 1
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash

if [[ -n ${SUDO_CALLS:-} ]]; then
  printf '%s\n' "$*" >>"$SUDO_CALLS"
fi
if [[ ${SUDO_FAIL:-0} == 1 ]]; then
  echo "sudo authentication failed" >&2
  exit 1
fi

exec "$@"
STUB
chmod +x "$stub_bin"/*

current_force_fixture="$fixtures/force-igpu-current"
historical_force_fixture="$fixtures/force-igpu-post-only"

# Strip the new package activation guards to recover the last unowned hook
# that omarchy-toggle-hybrid-gpu copied into /usr.
awk '
  /^# This hook is package-owned/ { skip = 1 }
  skip && /^\[\[ -x \/usr\/bin\/supergfxctl \]\] \|\| exit 0$/ { skip = 0; getline; next }
  !skip { print }
' "$ROOT/default/systemd/system-sleep/force-igpu" >"$current_force_fixture"

cat >"$historical_force_fixture" <<'HOOK'
#!/bin/bash

# Use the Vfio to Integrated trick to turn off NVIDIA dgpu when in integrated mode
# without needing to restart the computer. This is needed because computers like the Asus G14
# will wake after suspend in Hybrid mode, even if the system was in Integrated mode before
# suspending.

if [[ $1 == "post" ]]; then
  # small delay so the device is fully re-enumerated
  sleep 4

  # force-bind dGPU to vfio (fully detached from nvidia)
  /usr/bin/supergfxctl -m Vfio
  sleep 1

  # then go back to Integrated, which powers it off again
  /usr/bin/supergfxctl -m Integrated
fi
HOOK

[[ $(sha256sum "$current_force_fixture" | awk '{ print $1 }') == "d604e7c4903829563e45fc52188fc5602c3f1bc66e247f0a2cc0a974ed6e57db" ]] ||
  fail "the current force-iGPU fixture no longer matches the released hook"
[[ $(sha256sum "$historical_force_fixture" | awk '{ print $1 }') == "de620729f0c824225487ab988a53158de7336e4151d594c49641a99ed5740e6b" ]] ||
  fail "the historical force-iGPU fixture no longer matches the released hook"

new_case() {
  local name=$1

  case_root="$test_tmp/$name/root"
  transformed="$test_tmp/$name/migration.sh"
  mkdir -p \
    "$case_root/usr/lib/systemd/system-sleep" \
    "$case_root/usr/share/omarchy/default/systemd/system/supergfxd.service.d" \
    "$case_root/etc/systemd/system/supergfxd.service.d"

  sed \
    -e "s#/usr/lib#$case_root/usr/lib#g" \
    -e "s#/usr/share#$case_root/usr/share#g" \
    -e "s#/etc#$case_root/etc#g" \
    "$migration" >"$transformed"

  legacy_keyboard="$case_root/usr/lib/systemd/system-sleep/keyboard-backlight"
  packaged_keyboard="$case_root/usr/lib/systemd/system-sleep/omarchy-keyboard-backlight"
  legacy_force="$case_root/usr/lib/systemd/system-sleep/force-igpu"
  packaged_force="$case_root/usr/lib/systemd/system-sleep/omarchy-force-igpu"
  legacy_delay="$case_root/etc/systemd/system/supergfxd.service.d/delay-start.conf"
  packaged_delay="$case_root/usr/share/omarchy/default/systemd/system/supergfxd.service.d/delay-start.conf"
  marker="$case_root/etc/omarchy/force-igpu"
  delay_link="$case_root/etc/systemd/system/supergfxd.service.d/10-omarchy-delay-start.conf"
  sudo_calls="$test_tmp/$name/sudo-calls"
  : >"$sudo_calls"
}

install_packaged_payload() {
  install -Dm755 "$ROOT/default/systemd/system-sleep/keyboard-backlight" "$packaged_keyboard"
  install -Dm755 "$ROOT/default/systemd/system-sleep/force-igpu" "$packaged_force"
  install -Dm644 "$ROOT/default/systemd/system/supergfxd.service.d/delay-start.conf" "$packaged_delay"
}

install_current_legacy_state() {
  cp "$ROOT/default/systemd/system-sleep/keyboard-backlight" "$legacy_keyboard"
  cp "$current_force_fixture" "$legacy_force"
  cp "$ROOT/default/systemd/system/supergfxd.service.d/delay-start.conf" "$legacy_delay"
}

run_migration() {
  env \
    PATH="$stub_bin:$PATH" \
    PACMAN_ERROR_PATH="${PACMAN_ERROR_PATH:-}" \
    PACMAN_OWNED_PATHS="${PACMAN_OWNED_PATHS:-}" \
    SUDO_CALLS="$sudo_calls" \
    SUDO_FAIL="${SUDO_FAIL:-0}" \
    bash -euo pipefail "$transformed" >"$case_root.out" 2>"$case_root.err"
}

expect_migration_failure() {
  local expected_status=$1
  local status

  if run_migration; then
    fail "the sleep-hook migration unexpectedly succeeded"
  else
    status=$?
  fi
  (( status == expected_status )) || fail "the sleep-hook migration returned $status instead of $expected_status"
}

assert_no_activation_state() {
  [[ ! -e $marker && ! -L $marker ]] || fail "the sleep-hook transition invents force-iGPU activation state"
  [[ ! -e $delay_link && ! -L $delay_link ]] || fail "the sleep-hook transition invents a supergfxd delay"
}

new_case complete
install_packaged_payload
install_current_legacy_state
run_migration

[[ ! -e $legacy_keyboard ]] || fail "the package transition leaves the old keyboard hook unowned"
[[ ! -e $legacy_force ]] || fail "the package transition leaves the old force-iGPU hook unowned"
[[ ! -e $legacy_delay ]] || fail "the package transition leaves the old supergfxd drop-in unowned"
[[ -f $marker && ! -L $marker ]] || fail "the package transition loses force-iGPU activation state"
[[ -L $delay_link && $(readlink "$delay_link") == "$packaged_delay" ]] ||
  fail "the package transition does not activate the packaged supergfxd drop-in"
pass "legacy sleep hooks become package code plus explicit activation state"

run_migration
[[ -f $marker && ! -L $marker ]] || fail "rerunning the sleep-hook migration changes its marker"
[[ -L $delay_link && $(readlink "$delay_link") == "$packaged_delay" ]] ||
  fail "rerunning the sleep-hook migration changes its delay link"
pass "the sleep-hook transition is idempotent after completion"

new_case historical-force-only
install_packaged_payload
cp "$historical_force_fixture" "$legacy_force"
run_migration

[[ ! -e $legacy_force ]] || fail "the package transition misses the historical post-only force-iGPU hook"
[[ -f $marker && ! -L $marker ]] || fail "the historical force-iGPU hook does not become activation state"
[[ ! -e $delay_link && ! -L $delay_link ]] || fail "a force-hook-only transition invents a supergfxd delay"
pass "both released force-iGPU hooks transition without inventing delay state"

new_case delay-only
install_packaged_payload
cp "$ROOT/default/systemd/system/supergfxd.service.d/delay-start.conf" "$legacy_delay"
run_migration

[[ ! -e $legacy_delay ]] || fail "the delay-only transition leaves the old drop-in unowned"
[[ -L $delay_link && $(readlink "$delay_link") == "$packaged_delay" ]] ||
  fail "the delay-only transition does not activate the packaged drop-in"
[[ ! -e $marker && ! -L $marker ]] || fail "a delay-only transition enables the force-iGPU hook"
pass "force-hook and startup-delay state transition independently"

new_case no-legacy-state
install_packaged_payload
run_migration
assert_no_activation_state
[[ ! -s $sudo_calls ]] || fail "a system without legacy hooks is prompted for sudo"
pass "systems without legacy hooks gain no activation state"

new_case locally-modified
install_packaged_payload
printf 'locally changed keyboard hook\n' >"$legacy_keyboard"
printf 'locally changed force hook\n' >"$legacy_force"
printf 'locally changed delay\n' >"$legacy_delay"
run_migration

grep -qx 'locally changed keyboard hook' "$legacy_keyboard" || fail "the hook transition removes local keyboard state"
grep -qx 'locally changed force hook' "$legacy_force" || fail "the hook transition removes local force-iGPU state"
grep -qx 'locally changed delay' "$legacy_delay" || fail "the hook transition removes local supergfxd state"
assert_no_activation_state
pass "the sleep-hook transition preserves unknown local files"

new_case package-owned
install_packaged_payload
install_current_legacy_state
PACMAN_OWNED_PATHS="$legacy_keyboard:$legacy_force:$legacy_delay" run_migration

[[ -f $legacy_keyboard && -f $legacy_force && -f $legacy_delay ]] || fail "the hook transition removes package-owned files"
assert_no_activation_state
pass "the sleep-hook transition preserves files owned by another package"

new_case symlinks
install_packaged_payload
mkdir -p "$case_root/admin"
cp "$ROOT/default/systemd/system-sleep/keyboard-backlight" "$case_root/admin/keyboard"
cp "$current_force_fixture" "$case_root/admin/force"
cp "$ROOT/default/systemd/system/supergfxd.service.d/delay-start.conf" "$case_root/admin/delay"
ln -s "$case_root/admin/keyboard" "$legacy_keyboard"
ln -s "$case_root/admin/force" "$legacy_force"
ln -s "$case_root/admin/delay" "$legacy_delay"
run_migration

[[ -L $legacy_keyboard && $(readlink "$legacy_keyboard") == "$case_root/admin/keyboard" ]] || fail "the hook transition removes a keyboard symlink"
[[ -L $legacy_force && $(readlink "$legacy_force") == "$case_root/admin/force" ]] || fail "the hook transition removes a force-iGPU symlink"
[[ -L $legacy_delay && $(readlink "$legacy_delay") == "$case_root/admin/delay" ]] || fail "the hook transition removes a delay symlink"
assert_no_activation_state
pass "the sleep-hook transition never follows legacy symlinks"

for missing in keyboard force delay; do
  new_case "missing-$missing"
  install_packaged_payload

  case "$missing" in
    keyboard)
      cp "$ROOT/default/systemd/system-sleep/keyboard-backlight" "$legacy_keyboard"
      rm -f "$packaged_keyboard"
      expected_legacy=$legacy_keyboard
      ;;
    force)
      cp "$current_force_fixture" "$legacy_force"
      rm -f "$packaged_force"
      expected_legacy=$legacy_force
      ;;
    delay)
      cp "$ROOT/default/systemd/system/supergfxd.service.d/delay-start.conf" "$legacy_delay"
      rm -f "$packaged_delay"
      expected_legacy=$legacy_delay
      ;;
  esac

  expect_migration_failure 1
  [[ -f $expected_legacy ]] || fail "the migration removes $missing state without its package replacement"
  assert_no_activation_state
done
pass "missing package replacements keep the migration pending"

new_case resumed-transition
install_packaged_payload
cp "$current_force_fixture" "$legacy_force"
cp "$ROOT/default/systemd/system/supergfxd.service.d/delay-start.conf" "$legacy_delay"
install -Dm644 /dev/null "$marker"
ln -s "$packaged_delay" "$delay_link"
run_migration

[[ ! -e $legacy_force && ! -e $legacy_delay ]] || fail "the migration cannot finish an interrupted state transition"
[[ -f $marker && -L $delay_link ]] || fail "the migration damages already-created activation state"
pass "the sleep-hook transition resumes safely after interruption"

new_case destination-collision
install_packaged_payload
cp "$ROOT/default/systemd/system/supergfxd.service.d/delay-start.conf" "$legacy_delay"
printf 'administrator delay\n' >"$delay_link"
run_migration

grep -qx 'administrator delay' "$delay_link" || fail "the migration overwrites an administrator's delay drop-in"
[[ -f $legacy_delay ]] || fail "the migration removes the working legacy delay after a destination collision"
[[ ! -L $delay_link ]] || fail "the migration replaces administrator state with a package link"
pass "a delay destination collision preserves administrator and legacy state"

new_case marker-collision
install_packaged_payload
cp "$current_force_fixture" "$legacy_force"
mkdir -p "$marker"
run_migration

[[ -d $marker ]] || fail "the migration overwrites administrator state at the force-iGPU marker"
[[ -f $legacy_force ]] || fail "the migration removes the working force hook after a marker collision"
pass "a force-iGPU marker collision preserves administrator and legacy state"

new_case ownership-error
install_packaged_payload
cp "$ROOT/default/systemd/system-sleep/keyboard-backlight" "$legacy_keyboard"
PACMAN_ERROR_PATH="$legacy_keyboard" expect_migration_failure 2

[[ -f $legacy_keyboard ]] || fail "an ownership-query error removes the legacy hook"
assert_no_activation_state
grep -q 'Unable to verify package ownership' "$case_root.err" || fail "an ownership-query error is not reported"
pass "package ownership errors fail closed and keep the migration pending"

new_case sudo-error
install_packaged_payload
cp "$ROOT/default/systemd/system-sleep/keyboard-backlight" "$legacy_keyboard"
SUDO_FAIL=1 expect_migration_failure 2

[[ -f $legacy_keyboard ]] || fail "a sudo error removes the legacy hook"
assert_no_activation_state
pass "sudo errors fail closed and keep the migration pending"
