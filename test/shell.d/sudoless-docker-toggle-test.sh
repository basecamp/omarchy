#!/bin/bash
#
# Toggling sudoless Docker changes the docker group, which only takes effect on a
# reboot. The setup/remove commands must flag the reboot and offer to do it now
# (gum confirm), but defer it when OMARCHY_DEFER_REBOOT is set (the migration
# reuses them inside `omarchy update`, where omarchy-update-restart handles it).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
home="$test_dir/home"
stub_bin="$test_dir/bin"
mkdir -p "$home" "$stub_bin"

cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
printf '%s\n' "${STUB_GROUPS:-wheel input}"
STUB
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
cat >"$stub_bin/usermod" <<'STUB'
#!/bin/bash
echo "$@" >>"${USERMOD_CALLS:?}"
STUB
cat >"$stub_bin/gpasswd" <<'STUB'
#!/bin/bash
echo "$@" >>"${GPASSWD_CALLS:?}"
STUB
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
touch "${GUM_CALLED:?}"
exit "${GUM_ANSWER:-0}"
STUB
cat >"$stub_bin/omarchy-system-reboot" <<'STUB'
#!/bin/bash
touch "${REBOOT_CALLED:?}"
STUB
chmod +x "$stub_bin"/*

reboot_flag="$home/.local/state/omarchy/reboot-required"
gum_called="$test_dir/gum-called"
reboot_called="$test_dir/reboot-called"
gpasswd_calls="$test_dir/gpasswd-calls"
usermod_calls="$test_dir/usermod-calls"

run() { # command STUB_GROUPS GUM_ANSWER DEFER(0|1)
  rm -f "$reboot_flag" "$gum_called" "$reboot_called" "$gpasswd_calls" "$usermod_calls"
  local defer_env=()
  [[ ${4:-0} == 1 ]] && defer_env=(OMARCHY_DEFER_REBOOT=1)
  env HOME="$home" USER="tester" STUB_GROUPS="$2" GUM_ANSWER="$3" \
    GUM_CALLED="$gum_called" REBOOT_CALLED="$reboot_called" \
    GPASSWD_CALLS="$gpasswd_calls" USERMOD_CALLS="$usermod_calls" \
    PATH="$stub_bin:$ROOT/bin:$PATH" "${defer_env[@]}" \
    bash "$ROOT/bin/$1" >/dev/null 2>&1
}

# Remove, interactive, reboot confirmed -> group removed, flag set, reboot fired.
run omarchy-remove-security-sudoless-docker "wheel input docker" 0 0
grep -q -- "-d tester docker" "$gpasswd_calls" || fail "remove drops the user from the docker group"
[[ -f $reboot_flag ]] || fail "remove flags a reboot"
[[ -f $reboot_called ]] || fail "remove reboots when the prompt is confirmed"
pass "remove drops the group, flags a reboot, and reboots on confirm"

# Remove, interactive, reboot declined -> flag set, but no reboot.
run omarchy-remove-security-sudoless-docker "wheel input docker" 1 0
[[ -f $reboot_flag ]] || fail "remove still flags a reboot when the prompt is declined"
[[ ! -f $reboot_called ]] || fail "remove does not reboot when the prompt is declined"
pass "remove leaves the reboot to the user when declined"

# Remove, deferred (migration/update) -> flag set, prompt never shown.
run omarchy-remove-security-sudoless-docker "wheel input docker" 0 1
[[ -f $reboot_flag ]] || fail "deferred remove still flags a reboot"
[[ ! -f $gum_called ]] || fail "deferred remove must not prompt to reboot"
[[ ! -f $reboot_called ]] || fail "deferred remove must not reboot"
pass "deferred remove flags the reboot without prompting"

# Remove, already out of the group -> no-op, nothing flagged.
run omarchy-remove-security-sudoless-docker "wheel input" 0 0
[[ ! -f $gpasswd_calls ]] || fail "remove is a no-op when the user is not in the docker group"
[[ ! -f $reboot_flag ]] || fail "remove does not flag a reboot when nothing changed"
pass "remove is a no-op when sudoless Docker is already off"

# Setup, enable confirmed then reboot confirmed -> group added, flag set, reboot.
run omarchy-setup-security-sudoless-docker "wheel input" 0 0
grep -q -- "-aG docker tester" "$usermod_calls" || fail "setup adds the user to the docker group"
[[ -f $reboot_flag ]] || fail "setup flags a reboot"
[[ -f $reboot_called ]] || fail "setup reboots when the prompt is confirmed"
pass "setup adds the group, flags a reboot, and reboots on confirm"
