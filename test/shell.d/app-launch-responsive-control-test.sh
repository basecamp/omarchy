#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

control="$ROOT/bin/omarchy-app-launch-responsive-control"
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT

mock_core="$test_tmp/mock-core"
cat >"$mock_core" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$CONTROL_TEST_LOG"

case "${1:-}:${2:-}" in
  status:--json)
    pending=$(<"$CONTROL_TEST_PENDING")
    printf '{"ownership_pending":%s,"requested":false}\n' "$pending"
    ;;
  set:off)
    if [[ ${CONTROL_TEST_OFF_FAIL:-false} == true ]]; then
      exit 1
    fi
    printf '%s\n' false >"$CONTROL_TEST_PENDING"
    printf '%s\n' '{"operation":{"ok":true}}'
    ;;
  set:on)
    if [[ ${CONTROL_TEST_ON_FAIL:-false} == true ]]; then
      exit 1
    fi
    printf '%s\n' '{"operation":{"ok":true}}'
    ;;
  audit-config:--json | activate: | reconcile: | verify-removable:--json)
    printf '%s\n' '{"ok":true}'
    ;;
  probe:--json)
    printf '%s\n' '{"supported":true,"available":true}'
    ;;
  *)
    echo "unexpected mock core invocation: $*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$mock_core"

export CONTROL_TEST_LOG="$test_tmp/core.log"
export CONTROL_TEST_PENDING="$test_tmp/pending"
: >"$CONTROL_TEST_LOG"
printf '%s\n' false >"$CONTROL_TEST_PENDING"

(
  # Sourcing exposes the actual helper functions without running privileged main.
  source "$control"
  core="$mock_core"
  [[ $(status_field ownership_pending) == false ]] ||
    fail "status_field treats a valid false boolean as a command failure"
)
pass "control reads false JSON ownership booleans without jq -e ambiguity"

rollback_root="$test_tmp/rollback"
mkdir -p "$rollback_root/state" "$rollback_root/runtime"
touch "$rollback_root/config" "$rollback_root/unit" "$rollback_root/policy" \
  "$rollback_root/state/state.json"
printf '%s\n' true >"$CONTROL_TEST_PENDING"
: >"$CONTROL_TEST_LOG"
(
  source "$control"
  core="$mock_core"
  config="$rollback_root/config"
  unit="$rollback_root/unit"
  policy="$rollback_root/policy"
  wants="$rollback_root/wants"
  state_dir="$rollback_root/state"
  state_file="$state_dir/state.json"
  runtime_dir="$rollback_root/runtime"
  service_active() { return 1; }
  systemctl() { return 0; }
  reload_managers() { return 0; }
  rollback_incomplete_setup
)
grep -Fxq 'set off' "$CONTROL_TEST_LOG" ||
  fail "rollback skipped core restoration while ownership was pending"
grep -Fxq 'verify-removable --json' "$CONTROL_TEST_LOG" ||
  fail "rollback did not verify clean ownership after restoration"
[[ ! -e $rollback_root/config && ! -e $rollback_root/state ]] ||
  fail "verified incomplete setup artifacts were not removed"
pass "incomplete setup executes restore before verified cleanup"

stop_root="$test_tmp/stop-failure"
mkdir -p "$stop_root/state" "$stop_root/runtime"
touch "$stop_root/config" "$stop_root/unit" "$stop_root/policy" \
  "$stop_root/state/state.json"
printf '%s\n' true >"$CONTROL_TEST_PENDING"
if (
  source "$control"
  core="$mock_core"
  config="$stop_root/config"
  unit="$stop_root/unit"
  policy="$stop_root/policy"
  wants="$stop_root/wants"
  state_dir="$stop_root/state"
  state_file="$state_dir/state.json"
  runtime_dir="$stop_root/runtime"
  service_active() { return 0; }
  systemctl() { return 1; }
  reload_managers() { return 0; }
  rollback_incomplete_setup
); then
  fail "setup rollback succeeded despite a service that would not stop"
fi
[[ -e $stop_root/config && -e $stop_root/state/state.json ]] ||
  fail "setup rollback deleted recovery files while the service remained active"
pass "setup rollback retains every recovery artifact when stop fails"

drift_root="$test_tmp/drift-off"
mkdir -p "$drift_root"
touch "$drift_root/config"
: >"$CONTROL_TEST_LOG"
printf '%s\n' true >"$CONTROL_TEST_PENDING"
(
  source "$control"
  core="$mock_core"
  config="$drift_root/config"
  unit="$drift_root/missing-unit"
  policy="$drift_root/missing-policy"
  state_dir="$drift_root/missing-state"
  disable_existing
)
grep -Fxq 'set off' "$CONTROL_TEST_LOG" ||
  fail "OFF recovery was blocked by missing or drifted non-core artifacts"
pass "OFF remains directly actionable despite service/policy/template drift"

first_root="$test_tmp/first-apply"
mkdir -p "$first_root/source"
touch "$first_root/source/config.json" \
  "$first_root/source/omarchy-app-launch-responsive.service" \
  "$first_root/source/org.omarchy.app-launch-responsive.policy"
: >"$CONTROL_TEST_LOG"
# Simulate a failed first apply that initially reports rollback ownership. The
# setup transaction must retry OFF before deciding to retain recovery state.
printf '%s\n' true >"$CONTROL_TEST_PENDING"
export CONTROL_TEST_ON_FAIL=true
set +e
(
  source "$control"
  core="$mock_core"
  source_dir="$first_root/source"
  config="$first_root/config"
  unit="$first_root/unit"
  policy="$first_root/policy"
  wants="$first_root/wants"
  state_dir="$first_root/state"
  state_file="$state_dir/state.json"
  runtime_dir="$first_root/runtime"
  owned_files=("$config" "$unit" "$policy")
  owned_paths=("${owned_files[@]}" "$wants" "$state_dir" "$runtime_dir")
  active=false
  enabled=false
  service_active() { [[ $active == true ]]; }
  service_enabled() { [[ $enabled == true ]]; }
  install_templates() {
    touch "$config" "$unit" "$policy"
  }
  reload_managers() { return 0; }
  assert_installed_shape() { return 0; }
  assert_templates_current() { return 0; }
  systemctl() {
    if [[ $1 == "enable" ]]; then
      enabled=true
      active=true
      mkdir -p "$state_dir" "$runtime_dir"
      touch "$state_file"
      ln -s "$unit" "$wants"
    fi
    return 0
  }
  fresh_enable
)
first_rc=$?
set -e
unset CONTROL_TEST_ON_FAIL
((first_rc != 0 && first_rc != 125)) ||
  fail "clean first-apply failure did not preserve its original failure status"
[[ -e $first_root/config && -e $first_root/unit && -e $first_root/state/state.json ]] ||
  fail "clean first-apply failure left a partial persistent installation"
grep -Fxq 'set off' "$CONTROL_TEST_LOG" ||
  fail "clean first-apply failure was not finalized OFF"
pass "failed first apply retains a complete, clean, OFF backend"
