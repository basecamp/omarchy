#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/fix-synaptic-touchpad.sh"
all="$ROOT/install/hardware/all.sh"

grep -q 'run_logged .*hardware/fix-synaptic-touchpad.sh' "$all" ||
  fail "the synaptic touchpad quirk runs during hardware setup"
pass "the synaptic touchpad quirk runs during hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin"
modprobe_log="$test_tmp/modprobe.log"

# Only a real load is logged, so a case that expects nothing to happen can say
# so with an empty log even though the leaf always asks modprobe first whether
# psmouse resolves against the running kernel.
cat >"$test_tmp/bin/modprobe" <<'SH'
#!/bin/bash

if [[ $1 == "-qn" ]]; then
  exit "${TEST_MODPROBE_RESOLVES:-0}"
fi

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
    OMARCHY_SYNAPTIC_INPUT_DEVICES="$test_tmp/devices" \
    TEST_LOADED_MODULES="${1:-}" \
    TEST_MODPROBE_STATUS="${2:-0}" \
    TEST_MODPROBE_RESOLVES="${3:-0}" \
    bash -eE -c 'source "$1"' bash "$leaf"
}

run_fix
grep -q 'psmouse synaptics_intertouch=1' "$modprobe_log" ||
  fail "the synaptic touchpad quirk enables InterTouch on a booted machine"
pass "the synaptic touchpad quirk enables InterTouch on a booted machine"

# The install-breaking case: under arch-chroot the live kernel's modules are not
# the ones on disk, so psmouse does not resolve and there is nothing to load.
run_fix "" 0 1
if [[ -s $modprobe_log ]]; then
  fail "the synaptic touchpad quirk skips a kernel that cannot resolve psmouse"
fi
pass "the synaptic touchpad quirk skips a kernel that cannot resolve psmouse"

run_fix psmouse
if [[ -s $modprobe_log ]]; then
  fail "the synaptic touchpad quirk leaves an already-loaded psmouse alone"
fi
pass "the synaptic touchpad quirk leaves an already-loaded psmouse alone"

# An optional touchpad improvement never gets to halt an install, whatever the
# reason the module declines to load.
run_fix "" 1 2>/dev/null ||
  fail "the synaptic touchpad quirk survives a failing modprobe"
pass "the synaptic touchpad quirk survives a failing modprobe"
