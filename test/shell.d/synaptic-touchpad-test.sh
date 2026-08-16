#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/fix-synaptic-touchpad.sh"
all="$ROOT/install/hardware/all.sh"

grep -q 'hardware/fix-synaptic-touchpad.sh' "$all" ||
  fail "the synaptic touchpad quirk runs during hardware setup"
pass "the synaptic touchpad quirk runs during hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/modules"
modprobe_log="$test_tmp/modprobe.log"

cat >"$test_tmp/bin/modprobe" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$MODPROBE_LOG"
exit "${TEST_MODPROBE_STATUS:-0}"
SH

cat >"$test_tmp/bin/lsmod" <<'SH'
#!/bin/bash

printf '%s\n' 'Module                  Size  Used by'
printf '%s\n' "${TEST_LOADED_MODULES:-}"
SH

chmod +x "$test_tmp/bin"/*

printf '%s\n' 'N: Name="SynPS/2 Synaptics TouchPad"' >"$test_tmp/devices"

# Sourced under errexit the way run_logged runs it, so a failing modprobe would
# fail the run rather than be swallowed here.
run_fix() {
  : >"$modprobe_log"

  MODPROBE_LOG="$modprobe_log" \
    PATH="$test_tmp/bin:$PATH" \
    OMARCHY_SYNAPTIC_MODULES_DIR="${1:-$test_tmp/modules}" \
    OMARCHY_SYNAPTIC_INPUT_DEVICES="$test_tmp/devices" \
    TEST_LOADED_MODULES="${2:-}" \
    TEST_MODPROBE_STATUS="${3:-0}" \
    bash -eE -c 'source "$1"' bash "$leaf"
}

run_fix
grep -q 'psmouse synaptics_intertouch=1' "$modprobe_log" ||
  fail "the synaptic touchpad quirk enables InterTouch on a booted machine"
pass "the synaptic touchpad quirk enables InterTouch on a booted machine"

run_fix "$test_tmp/absent"
if [[ -s $modprobe_log ]]; then
  fail "the synaptic touchpad quirk skips a kernel whose modules are unreachable"
fi
pass "the synaptic touchpad quirk skips a kernel whose modules are unreachable"

run_fix "" psmouse
if [[ -s $modprobe_log ]]; then
  fail "the synaptic touchpad quirk leaves an already-loaded psmouse alone"
fi
pass "the synaptic touchpad quirk leaves an already-loaded psmouse alone"

# An optional touchpad improvement never gets to halt an install, whatever the
# reason the module declines to load.
run_fix "" "" 1 2>/dev/null ||
  fail "the synaptic touchpad quirk survives a failing modprobe"
pass "the synaptic touchpad quirk survives a failing modprobe"
