#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Install and activate zram swap' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "zram activation migration exists"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
calls="$test_dir/calls.log"
package_installed="$test_dir/zram-generator.installed"
swap_active="$test_dir/dev-zram0.swap.active"
state_dir="$test_dir/state"
test_root="$test_dir/omarchy"
migration_name=$(basename "$migration")
default_home="$test_dir/home"
second_user_home="$test_dir/second-user-home"
default_marker="$default_home/.local/state/omarchy/migrations/$migration_name"
second_user_marker="$second_user_home/.local/state/omarchy/migrations/$migration_name"
mkdir -p "$stub_bin" "$state_dir" "$test_root/migrations"
cp "$migration" "$test_root/migrations/$migration_name"

cat >"$stub_bin/omarchy-pkg-missing" <<'STUB'
#!/bin/bash

printf 'pkg-missing\t%s\n' "$*" >>"$TEST_CALLS"
[[ ! -e $TEST_PACKAGE_INSTALLED ]]
STUB

cat >"$stub_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash

printf 'pkg-add\t%s\n' "$*" >>"$TEST_CALLS"
(( ${PKG_ADD_FAIL:-0} == 0 )) || exit 55
touch "$TEST_PACKAGE_INSTALLED"
STUB

cat >"$stub_bin/systemctl" <<'STUB'
#!/bin/bash

printf 'systemctl\t%s\n' "$*" >>"$TEST_CALLS"

case "$1" in
  is-active)
    [[ -e $TEST_SWAP_ACTIVE ]]
    ;;
  daemon-reload)
    exit "${DAEMON_RELOAD_STATUS:-0}"
    ;;
  start)
    (( ${START_STATUS:-0} == 0 )) || exit "$START_STATUS"
    (( ${ACTIVATE_AFTER_START:-1} == 0 )) || touch "$TEST_SWAP_ACTIVE"
    ;;
esac
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash

printf 'sudo\t%s\n' "$*" >>"$TEST_CALLS"
exec "$@"
STUB

cat >"$stub_bin/omarchy-state" <<'STUB'
#!/bin/bash

printf 'state\t%s\n' "$*" >>"$TEST_CALLS"
[[ $1 == "set" ]] && touch "$TEST_STATE_DIR/$2"
STUB

cat >"$stub_bin/omarchy-notification-dismiss" <<'STUB'
#!/bin/bash

printf 'notification-dismiss\t%s\n' "$*" >>"$TEST_CALLS"
STUB

chmod +x "$stub_bin"/*

export TEST_CALLS="$calls"
export TEST_PACKAGE_INSTALLED="$package_installed"
export TEST_SWAP_ACTIVE="$swap_active"
export TEST_STATE_DIR="$state_dir"

reset_case() {
  local installed="$1" active="$2"

  : >"$calls"
  rm -f \
    "$package_installed" \
    "$swap_active" \
    "$state_dir/reboot-required" \
    "$default_marker" \
    "$second_user_marker"
  (( installed == 0 )) || touch "$package_installed"
  (( active == 0 )) || touch "$swap_active"
}

run_migration() {
  local home="${1:-$default_home}"

  mkdir -p "$home"
  HOME="$home" \
  OMARCHY_PATH="$test_root" \
  PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-migrate" >/dev/null
}

assert_no_activation_work() {
  ! grep -Eq $'systemctl\t(daemon-reload|start)' "$calls" ||
    fail "active zram swap is not reloaded or restarted" "$(cat "$calls")"
  ! grep -q '^sudo' "$calls" ||
    fail "active zram swap needs no privileged command" "$(cat "$calls")"
  [[ ! -e $state_dir/reboot-required ]] ||
    fail "active zram swap does not request a reboot" "$(cat "$calls")"
}

assert_privileged_activation() {
  grep -Fxq $'sudo\tsystemctl daemon-reload' "$calls" ||
    fail "migration reloads systemd through sudo" "$(cat "$calls")"
  grep -Fxq $'sudo\tsystemctl start dev-zram0.swap' "$calls" ||
    fail "migration starts zram swap through sudo" "$(cat "$calls")"
}

reset_case 0 0
run_migration
[[ -e $package_installed ]] || fail "migration installs zram-generator when it is missing" "$(cat "$calls")"
[[ -e $swap_active ]] || fail "migration activates zram swap after package installation" "$(cat "$calls")"
grep -Fxq $'pkg-add\tzram-generator' "$calls" ||
  fail "migration uses omarchy-pkg-add for zram-generator" "$(cat "$calls")"
grep -Fxq $'systemctl\tdaemon-reload' "$calls" ||
  fail "migration reloads systemd after package installation" "$(cat "$calls")"
grep -Fxq $'systemctl\tstart dev-zram0.swap' "$calls" ||
  fail "migration starts the generated swap unit" "$(cat "$calls")"
assert_privileged_activation
[[ -e $default_marker ]] || fail "successful zram repair is marked complete by omarchy-migrate"
grep -Fxq $'notification-dismiss\tOmarchy Migrations' "$calls" ||
  fail "successful migration dismisses notifications through the test stub" "$(cat "$calls")"
pass "migration installs and activates missing zram support"

: >"$calls"
run_migration "$second_user_home"
! grep -Eq $'^(pkg-add|sudo|systemctl\t(daemon-reload|start)|state)' "$calls" ||
  fail "a second user leaves the repaired machine unchanged" "$(cat "$calls")"
[[ -e $second_user_marker ]] || fail "a second user records the machine-wide repair as complete"
pass "migration is a multi-user no-op after repair"

reset_case 1 1
run_migration
! grep -q '^pkg-add' "$calls" || fail "installed zram-generator is not reinstalled" "$(cat "$calls")"
assert_no_activation_work
pass "migration leaves active zram swap unchanged"

reset_case 1 0
run_migration
! grep -q '^pkg-add' "$calls" || fail "installed zram-generator is not reinstalled" "$(cat "$calls")"
[[ -e $swap_active ]] || fail "inactive zram swap is activated" "$(cat "$calls")"
grep -Fxq $'systemctl\tdaemon-reload' "$calls" || fail "inactive zram swap reloads systemd" "$(cat "$calls")"
grep -Fxq $'systemctl\tstart dev-zram0.swap' "$calls" || fail "inactive zram swap is started" "$(cat "$calls")"
assert_privileged_activation
pass "migration activates zram when the package is already installed"

reset_case 1 0
DAEMON_RELOAD_STATUS=1 run_migration
[[ -e $state_dir/reboot-required ]] ||
  fail "a failed systemd reload requests a reboot" "$(cat "$calls")"
[[ -e $default_marker ]] ||
  fail "a reboot-deferred zram repair is marked complete by omarchy-migrate" "$(cat "$calls")"
! grep -Fxq $'systemctl\tstart dev-zram0.swap' "$calls" ||
  fail "a failed systemd reload does not try to start the unit" "$(cat "$calls")"
pass "migration finishes cleanly when systemd cannot reload"

reset_case 1 0
START_STATUS=1 run_migration
[[ -e $state_dir/reboot-required ]] ||
  fail "a failed swap-unit start requests a reboot" "$(cat "$calls")"
pass "migration finishes cleanly when zram swap cannot start"

reset_case 1 0
ACTIVATE_AFTER_START=0 run_migration
[[ -e $state_dir/reboot-required ]] ||
  fail "a swap unit that stays inactive requests a reboot" "$(cat "$calls")"
pass "migration verifies live activation and falls back to reboot"

reset_case 0 0
if PKG_ADD_FAIL=1 run_migration; then
  fail "package installation failure keeps the migration pending" "$(cat "$calls")"
fi
[[ ! -e $default_marker ]] ||
  fail "package installation failure is not marked complete by omarchy-migrate" "$(cat "$calls")"
[[ ! -e $state_dir/reboot-required ]] ||
  fail "package installation failure is not converted to a reboot request" "$(cat "$calls")"
! grep -q '^systemctl' "$calls" ||
  fail "package installation failure stops before systemd changes" "$(cat "$calls")"
! grep -q '^notification-dismiss' "$calls" ||
  fail "package installation failure does not dismiss migration notifications" "$(cat "$calls")"
run_migration
[[ -e $default_marker ]] || fail "a repaired package installation retry is marked complete"
[[ -e $package_installed && -e $swap_active ]] ||
  fail "a package installation failure is retried on the next migration run" "$(cat "$calls")"
pass "package installation failure remains pending and retries successfully"
