#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_bin=$(mktemp -d)
log_file=$(mktemp)

cleanup() {
  rm -rf "$test_bin"
  rm -f "$log_file"
}
trap cleanup EXIT

# Presence is stubbed rather than probed so the branch under test is decided by
# the test and not by whether the developer's own machine has Voxtype installed.
cat >"$test_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
[[ -n $TEST_VOXTYPE_PRESENT ]] && exit 1
exit 0
STUB

cat >"$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'STUB'
#!/bin/bash
echo "present:$*" >>"$TEST_LOG"
STUB

cat >"$test_bin/omarchy-restart-shell" <<'STUB'
#!/bin/bash
echo "restart-shell" >>"$TEST_LOG"
STUB

chmod +x "$test_bin"/*

run_model() {
  : >"$log_file"
  TEST_VOXTYPE_PRESENT="$1" TEST_LOG="$log_file" PATH="$test_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-voxtype-model"
}

run_model ""

grep -qx 'present:omarchy-voxtype-install' "$log_file" ||
  fail "missing Voxtype routes the model picker to the installer" "$(cat "$log_file")"
grep -q 'voxtype setup model' "$log_file" &&
  fail "missing Voxtype does not run the model picker"
grep -qx 'restart-shell' "$log_file" &&
  fail "missing Voxtype does not restart the shell"

run_model 1

grep -qx 'present:voxtype setup model' "$log_file" ||
  fail "installed Voxtype opens the model picker" "$(cat "$log_file")"
grep -qx 'restart-shell' "$log_file" ||
  fail "installed Voxtype restarts the shell to pick up the new model"
grep -q 'omarchy-voxtype-install' "$log_file" &&
  fail "installed Voxtype does not re-run the installer"

pass "Voxtype model picker guards against a missing Voxtype"
