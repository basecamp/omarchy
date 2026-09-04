#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

detector="$ROOT/bin/omarchy-hw-framework13-ai300"
leaf="$ROOT/install/hardware/framework/fix-framework13-ai300-mic.sh"
migration="$ROOT/migrations/1788345224.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

vendor_file="$test_tmp/sys_vendor"
product_file="$test_tmp/product_name"

run_detector() {
  OMARCHY_DMI_SYS_VENDOR="$vendor_file" \
    OMARCHY_DMI_PRODUCT_NAME="$product_file" \
    "$detector"
}

assert_detector_rejects() {
  local vendor="$1"
  local product="$2"

  printf '%s\n' "$vendor" >"$vendor_file"
  printf '%s\n' "$product" >"$product_file"

  if run_detector; then
    fail "non-target DMI data matches" "$vendor / $product"
  fi
}

printf '%s\n' 'Framework' >"$vendor_file"
printf '%s\n' 'Laptop 13 (AMD Ryzen AI 300 Series)' >"$product_file"

run_detector || fail "exact Framework Laptop 13 AMD Ryzen AI 300 DMI data matches"

assert_detector_rejects 'Not Framework' 'Laptop 13 (AMD Ryzen AI 300 Series)'
assert_detector_rejects 'Framework' 'Laptop 16 (AMD Ryzen AI 300 Series)'
assert_detector_rejects 'Framework' 'Laptop 13 (AMD Ryzen AI 300 Series) Pro'

rm -f "$vendor_file" "$product_file"
if run_detector; then
  fail "missing DMI data is rejected"
fi
pass "detector accepts only the exact target DMI and fails closed"

leaf_registration='run_logged "$OMARCHY_INSTALL/hardware/framework/fix-framework13-ai300-mic.sh"'
grep -Fxq "$leaf_registration" "$ROOT/install/hardware/all.sh" ||
  fail "Framework 13 AI 300 microphone fix is registered with hardware setup"
migration_name=$(basename "$migration")
grep -Fq 'source "$OMARCHY_PATH/install/hardware/framework/fix-framework13-ai300-mic.sh"' "$migration" ||
  fail "the migration sources the Framework 13 AI 300 microphone leaf"
[[ $(stat -c '%a' "$migration") == "644" ]] || fail "the migration has mode 0644"
pass "fresh hardware setup and the migration reuse the microphone fix"

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
result="$test_tmp/result"
config="$test_tmp/omarchy-framework13-ai300-mic.conf"
marker="$test_tmp/var/lib/omarchy/hardware/framework13-ai300-mic-fix"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash

echo 'limine-mkinitcpio' >>"$TEST_LOG"
exit "${TEST_REBUILD_STATUS:-0}"
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
exit "${TEST_STATE_STATUS:-0}"
SH

cat >"$stub_bin/omarchy-notification-dismiss" <<'SH'
#!/bin/bash

exit 0
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local vendor="${1:-Framework}"
  local product="${2:-Laptop 13 (AMD Ryzen AI 300 Series)}"
  local rebuild_status="${3:-0}"

  printf '%s\n' "$vendor" >"$vendor_file"
  printf '%s\n' "$product" >"$product_file"
  : >"$calls"
  : >"$result"

  PATH="$stub_bin:$ROOT/bin:$PATH" \
    TEST_LOG="$calls" \
    TEST_RESULT="$result" \
    TEST_REBUILD_STATUS="$rebuild_status" \
    OMARCHY_DMI_SYS_VENDOR="$vendor_file" \
    OMARCHY_DMI_PRODUCT_NAME="$product_file" \
    OMARCHY_FRAMEWORK13_AI300_MIC_CONF="$config" \
    OMARCHY_FRAMEWORK13_AI300_MIC_REBUILD_MARKER="$marker" \
    bash -euo pipefail -c '
      source "$1"
      printf "%s\n" "$OMARCHY_FRAMEWORK13_AI300_MIC_REBUILT" >"$TEST_RESULT"
    ' bash "$leaf"
}

run_leaf 'Not Framework' || fail "the hardware leaf succeeds as a no-op on other systems"
[[ ! -e $config ]] || fail "a nonmatching system does not write the module configuration"
[[ ! -e $marker ]] || fail "a nonmatching system does not create the rebuild marker"
[[ ! -s $calls ]] || fail "a nonmatching system performs no privileged writes or rebuilds" "$(cat "$calls")"
[[ $(<"$result") == "0" ]] || fail "a nonmatching system reports no rebuild"
pass "hardware leaf makes no changes on nonmatching systems"

run_leaf || fail "the hardware leaf applies on the exact target"

expected_directives=$'blacklist snd_acp70\nblacklist snd_acp_pci'
actual_directives=$(sed -E '/^[[:space:]]*(#|$)/d' "$config")
[[ $actual_directives == "$expected_directives" ]] ||
  fail "the module configuration contains exactly the two required active directives" "$actual_directives"
[[ $(stat -c '%a' "$config") == "644" ]] || fail "the module configuration has mode 0644"
[[ -f $marker ]] || fail "a successful rebuild creates the machine-wide marker"
[[ $(<"$result") == "1" ]] || fail "a successful rebuild reports a change"
[[ $(grep -c '^limine-mkinitcpio$' "$calls") == "1" ]] ||
  fail "initial configuration rebuilds the initramfs exactly once" "$(cat "$calls")"
pass "matching hardware installs the blacklist and records a successful rebuild"

run_leaf || fail "identical configuration with a marker succeeds"
[[ ! -s $calls ]] || fail "identical configuration with a marker is a complete no-op" "$(cat "$calls")"
[[ $(<"$result") == "0" ]] || fail "a no-op reports no rebuild"
pass "identical configuration with a marker is a complete no-op"

rm -f "$marker"
run_leaf || fail "existing configuration without a marker rebuilds"
[[ $(grep -c '^limine-mkinitcpio$' "$calls") == "1" ]] ||
  fail "existing configuration without a marker rebuilds exactly once" "$(cat "$calls")"
[[ -f $marker ]] || fail "the missing marker is recreated after rebuilding"
[[ $(<"$result") == "1" ]] || fail "the marker-repair rebuild reports a change"
pass "existing configuration without a marker rebuilds once"

printf '%s\n' 'blacklist old_framework_audio_module' >"$config"
run_leaf 'Framework' 'Laptop 13 (AMD Ryzen AI 300 Series)' 1 &&
  fail "a failed initramfs rebuild fails the hardware leaf"
[[ ! -s $result ]] || fail "a failed rebuild does not complete or report success"
[[ ! -e $marker ]] || fail "configuration replacement invalidates the old marker before rebuilding"
[[ $(sed -E '/^[[:space:]]*(#|$)/d' "$config") == "$expected_directives" ]] ||
  fail "the replacement configuration contains exactly the required active directives"

marker_removal_line=$(grep -n $'^sudo\trm\t-f\t'"$marker"'$' "$calls" | cut -d: -f1)
config_install_line=$(grep -En $'^sudo\tinstall\t-Dm0?644\t/dev/stdin\t'"$config"'$' "$calls" | cut -d: -f1)
rebuild_line=$(grep -n '^limine-mkinitcpio$' "$calls" | cut -d: -f1)
[[ -n $marker_removal_line && -n $config_install_line && -n $rebuild_line ]] ||
  fail "configuration replacement records marker removal, install, and rebuild" "$(cat "$calls")"
(( marker_removal_line < config_install_line && config_install_line < rebuild_line )) ||
  fail "configuration replacement invalidates the marker before changing configuration"

run_leaf || fail "a rebuild failure is retried on the next run"
[[ -f $marker ]] || fail "a successful retry creates the marker"
[[ $(<"$result") == "1" ]] || fail "a successful retry reports a change"
[[ $(grep -c '^limine-mkinitcpio$' "$calls") == "1" ]] ||
  fail "the retry rebuilds the initramfs exactly once" "$(cat "$calls")"
pass "configuration replacement invalidates the marker and failed rebuilds retry"

migration_root="$test_tmp/migration-root"
migration_state="$test_tmp/migration-state"
mkdir -p "$migration_root/migrations" "$migration_root/install/hardware/framework"
ln -s "$migration" "$migration_root/migrations/$migration_name"
ln -s "$leaf" "$migration_root/install/hardware/framework/fix-framework13-ai300-mic.sh"

run_migrator() {
  local state_dir="$1"
  local vendor="${2:-Framework}"
  local product="${3:-Laptop 13 (AMD Ryzen AI 300 Series)}"
  local rebuild_status="${4:-0}"
  local state_status="${5:-0}"

  printf '%s\n' "$vendor" >"$vendor_file"
  printf '%s\n' "$product" >"$product_file"
  : >"$calls"

  PATH="$stub_bin:$ROOT/bin:$PATH" \
    TEST_LOG="$calls" \
    TEST_REBUILD_STATUS="$rebuild_status" \
    TEST_STATE_STATUS="$state_status" \
    OMARCHY_PATH="$migration_root" \
    OMARCHY_MIGRATION_STATE="$state_dir" \
    OMARCHY_DMI_SYS_VENDOR="$vendor_file" \
    OMARCHY_DMI_PRODUCT_NAME="$product_file" \
    OMARCHY_FRAMEWORK13_AI300_MIC_CONF="$config" \
    OMARCHY_FRAMEWORK13_AI300_MIC_REBUILD_MARKER="$marker" \
    "$ROOT/bin/omarchy-migrate" >/dev/null
}

printf '%s\n' 'blacklist stale_framework_audio_module' >"$config"
mkdir -p "$(dirname "$marker")"
touch "$marker"
run_migrator "$migration_state" 'Framework' 'Laptop 13 (AMD Ryzen AI 300 Series)' 1 &&
  fail "a failed rebuild fails the migration runner"
[[ ! -e $migration_state/$migration_name ]] || fail "a failed migration is not marked complete"
[[ ! -e $marker ]] || fail "a failed migration leaves the rebuild marker absent"
if grep -Fq $'omarchy-state\tset\treboot-required' "$calls"; then
  fail "a failed migration does not request a reboot" "$(cat "$calls")"
fi

pending_output=$(
  OMARCHY_PATH="$migration_root" \
    OMARCHY_MIGRATION_STATE="$migration_state" \
    "$ROOT/bin/omarchy-migrate" --pending
) || fail "the failed migration remains pending"
[[ $pending_output == "$migration_name" ]] ||
  fail "the pending migration is the Framework microphone fix" "$pending_output"

run_migrator "$migration_state" || fail "the pending migration retries successfully"
[[ -f $migration_state/$migration_name ]] || fail "a successful retry marks the migration complete"
[[ -f $marker ]] || fail "a successful migration retry creates the rebuild marker"
grep -Fxq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "a successful migration retry requests a reboot" "$(cat "$calls")"
migration_rebuild_line=$(grep -n '^limine-mkinitcpio$' "$calls" | cut -d: -f1)
reboot_state_line=$(grep -n $'^omarchy-state\tset\treboot-required$' "$calls" | cut -d: -f1)
(( migration_rebuild_line < reboot_state_line )) ||
  fail "the migration requests a reboot only after the successful rebuild"
pass "a failed migration remains pending and requests a reboot only after retrying successfully"

state_failure_state="$test_tmp/state-failure-migration-state"
rm -f "$marker"
run_migrator "$state_failure_state" 'Framework' 'Laptop 13 (AMD Ryzen AI 300 Series)' 0 1 &&
  fail "a failed reboot-state write fails the migration runner"
[[ ! -e $state_failure_state/$migration_name ]] || fail "a failed reboot-state write leaves the migration pending"
[[ -f $marker ]] || fail "a reboot-state failure preserves the successful machine rebuild"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "the reboot-state failure happens after rebuilding the initramfs" "$(cat "$calls")"
grep -Fxq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the failed migration attempted to record the required reboot" "$(cat "$calls")"

run_migrator "$state_failure_state" || fail "a failed reboot-state write retries successfully"
[[ -f $state_failure_state/$migration_name ]] || fail "a successful reboot-state retry marks the migration complete"
if grep -Fq 'limine-mkinitcpio' "$calls"; then
  fail "a reboot-state retry does not repeat the successful machine rebuild" "$(cat "$calls")"
fi
grep -Fxq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "a reboot-state retry records the required reboot" "$(cat "$calls")"
pass "a reboot-state failure retries the flag without repeating the machine rebuild"

second_user_state="$test_tmp/second-user-migration-state"
run_migrator "$second_user_state" || fail "another user completes the migration on an already-fixed machine"
[[ -f $second_user_state/$migration_name ]] || fail "another user's migration is marked complete"
if grep -Fq 'limine-mkinitcpio' "$calls"; then
  fail "an already-fixed machine does not rebuild for another user" "$(cat "$calls")"
fi
grep -Fxq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "another user on the target hardware is also asked to reboot" "$(cat "$calls")"

nonmatching_state="$test_tmp/nonmatching-migration-state"
run_migrator "$nonmatching_state" 'Not Framework' || fail "nonmatching machines complete the migration"
[[ -f $nonmatching_state/$migration_name ]] || fail "the nonmatching migration is marked complete"
[[ ! -s $calls ]] || fail "nonmatching machines do not request a reboot" "$(cat "$calls")"
pass "already-applied target machines request a reboot without rebuilding, while nonmatching machines remain no-ops"
