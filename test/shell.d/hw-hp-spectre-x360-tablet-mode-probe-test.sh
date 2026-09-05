#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

probe="$ROOT/bin/omarchy-hw-hp-spectre-x360-tablet-mode-probe"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Load the probe as a module despite its lack of a .py suffix, the same way the
# agent-usage scanner tests load their collectors, so the real discovery,
# decode, and classification code runs here instead of a stub.
load='
import importlib.util, sys
from importlib.machinery import SourceFileLoader
spec = importlib.util.spec_from_loader("probe", SourceFileLoader("probe", sys.argv[1]))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
'

py() { python3 -c "$load"$'\n'"$1" "$probe" "${@:2}"; }

# EVIOCGSW(8) has one correct value; recompute it the kernel's way and pin it so
# a typo in the ioctl direction, size, or type is caught.
py '
assert probe.EVIOCGSW == (2 << 30) | (8 << 16) | (ord("E") << 8) | 0x1B
assert probe.EVIOCGSW == 0x8008451B, hex(probe.EVIOCGSW)
'
pass "the probe encodes EVIOCGSW(8) as 0x8008451b"

py '
assert probe.classify([1, 1, 1]) == "STUCK"
assert probe.classify([1]) == "STUCK"
assert probe.classify([0, 0]) == "OK"
assert probe.classify([0, 1, 0]) == "OK"
assert probe.classify([1, 0]) == "OK"
'
pass "a reading that never leaves tablet mode is STUCK; any change is OK"

# The bit decode: SW_TABLET_MODE is bit 1 of byte 0 of the EVIOCGSW buffer.
py '
def reading(byte0):
    return (byte0 >> probe.SW_TABLET_MODE_BIT) & 1
assert reading(0b00) == 0
assert reading(0b10) == 1
assert reading(0b01) == 0  # SW_LID, not tablet mode
assert reading(0b11) == 1
'
pass "the probe reads SW_TABLET_MODE from bit 1 of the switch state"

# The poll loop runs against an injected reader and clock, so its windowing and
# set-collecting logic is exercised without a real evdev node.
py '
ticks = iter([0.0, 1.0, 2.0, 3.0, 16.0])
values = iter([1, 1, 0])
seen = probe.poll_tablet_mode(
    lambda: next(values),
    duration=15.0,
    interval=0.0,
    clock=lambda: next(ticks),
    sleep=lambda _: None,
)
assert seen == {0, 1}, seen
'
pass "poll_tablet_mode collects every value seen before the window closes"

# Device discovery parses /proc/bus/input/devices; feed it fixtures.
present="$tmp_dir/devices-present"
cat >"$present" <<'DEVICES'
I: Bus=0011 Vendor=0001 Product=0001 Version=ab41
N: Name="AT Translated Set 2 keyboard"
H: Handlers=sysrq kbd event0

I: Bus=0019 Vendor=0000 Product=0000 Version=0000
N: Name="Intel HID switches"
H: Handlers=event7

I: Bus=0019 Vendor=0000 Product=0000 Version=0000
N: Name="Video Bus"
H: Handlers=kbd event8
DEVICES

absent="$tmp_dir/devices-absent"
cat >"$absent" <<'DEVICES'
I: Bus=0011 Vendor=0001 Product=0001 Version=ab41
N: Name="AT Translated Set 2 keyboard"
H: Handlers=sysrq kbd event0
DEVICES

py '
import sys
assert probe.find_switch_device(sys.argv[2]) == "/dev/input/event7"
assert probe.find_switch_device(sys.argv[3]) is None
assert probe.find_switch_device(sys.argv[4]) is None
' "$present" "$absent" "$tmp_dir/does-not-exist"
pass "find_switch_device resolves the Intel HID switches event node or reports nothing"

# End to end through the CLI: --samples replays a sequence, --proc-devices with
# no match reports NOT_FOUND, an unreadable --device reports NO_PERMISSION.
[[ $("$probe" --samples 1,1,1) == "STUCK" ]] || fail "--samples 1,1,1 prints STUCK"
[[ $("$probe" --samples 0,1,1) == "OK" ]] || fail "--samples 0,1,1 prints OK"
pass "the probe classifies a replayed --samples sequence"

[[ $("$probe" --proc-devices "$absent") == "NOT_FOUND" ]] ||
  fail "a proc table without the switch prints NOT_FOUND"
[[ $("$probe" --proc-devices "$tmp_dir/does-not-exist") == "NOT_FOUND" ]] ||
  fail "a missing proc table prints NOT_FOUND"
pass "the probe prints NOT_FOUND when the switch device is absent"

unreadable="$tmp_dir/unreadable-switch"
: >"$unreadable"
chmod 000 "$unreadable"
if (( EUID == 0 )); then
  pass "skipping NO_PERMISSION check as root (mode bits do not apply)"
else
  [[ $("$probe" --device "$unreadable") == "NO_PERMISSION" ]] ||
    fail "an unreadable switch device prints NO_PERMISSION"
  pass "the probe prints NO_PERMISSION when the switch device cannot be opened"
fi
