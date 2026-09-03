#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-btusb-autosuspend.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1787262778.sh"

grep -q 'apple/fix-btusb-autosuspend.sh' "$all" ||
  fail "the btusb autosuspend fix runs during hardware setup"
pass "the btusb autosuspend fix runs during hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
conf="$test_tmp/etc/modprobe.d/btusb-autosuspend.conf"
mkdir -p "$stub_bin" "$test_tmp/dmi"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
if (( ${T2_HARDWARE:-0} == 1 || ${BT_PCIE:-0} == 1 )); then
  echo '04:00.0 Network controller [0280]: Broadcom Inc. Bluetooth [14e4:5fa0]'
fi
if (( ${T2_HARDWARE:-0} == 1 )); then
  echo '01:00.0 Bridge [0680]: Apple Inc. T2 Security Chip [106b:1801]'
fi
if [[ -n ${WIFI_ID:-} ]]; then
  echo "03:00.0 Network controller [0280]: Broadcom Inc. Wireless [14e4:$WIFI_ID]"
fi
for _ in {1..4096}; do
  echo '02:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local vendor="$1" wifi_id="${2:-}" t2="${3:-0}" bt_pcie="${4:-0}"
  rm -rf "$test_tmp/etc"
  mkdir -p "$test_tmp/etc"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"

  local script="$test_tmp/leaf.sh"
  sed -e "s|/sys/class/dmi/id/sys_vendor|$test_tmp/dmi/sys_vendor|g" \
      -e "s|/etc/modprobe.d|$test_tmp/etc/modprobe.d|g" \
      "$leaf" >"$script"

  WIFI_ID="$wifi_id" T2_HARDWARE="$t2" BT_PCIE="$bt_pcie" PATH="$stub_bin:$PATH" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

# T2 Bluetooth is PCIe (hci_bcm4377), not btusb -- this option has nothing to
# act on there, and applying it would only cost battery on some other USB
# device that happens to autosuspend.
run_leaf "Apple Inc." 4488 1 >/dev/null
[[ ! -f $conf ]] || fail "a T2 Mac is left alone; its Bluetooth isn't on btusb"
pass "a T2 Mac is left alone; its Bluetooth isn't on btusb"

# Apple Silicon Macs also run Bluetooth over PCIe (hci_bcm4377) with no T2
# bridge chip at all -- the gate has to see that directly, not infer it from
# T2's absence.
run_leaf "Apple Inc." 4425 0 1 >/dev/null
[[ ! -f $conf ]] || fail "an Apple Silicon Mac is left alone; its Bluetooth isn't on btusb either"
pass "an Apple Silicon Mac is left alone; its Bluetooth isn't on btusb either"

# A listed Wi-Fi ID with PCIe Bluetooth and no T2 bridge is the only shape where
# the Bluetooth function's own ID and the old bridge proxy disagree.
run_leaf "Apple Inc." 4464 0 1 >/dev/null
[[ ! -f $conf ]] || fail "a Mac with a listed Wi-Fi part but PCIe Bluetooth is left alone"
pass "a Mac with a listed Wi-Fi part but PCIe Bluetooth is left alone"

run_leaf "Apple Inc." 4464 0 0 >/dev/null
[[ -f $conf ]] || fail "the same Wi-Fi part with USB Bluetooth gets the quirk"
pass "the same Wi-Fi part with USB Bluetooth gets the quirk"

run_leaf "Apple Inc." 43ba 0 >/dev/null
grep -qx 'options btusb enable_autosuspend=n' "$conf" 2>/dev/null ||
  fail "a brcmfmac Mac without a T2 gets the quirk" "$(ls -R "$test_tmp/etc" 2>&1)"
pass "a brcmfmac Mac without a T2 gets the quirk"

# 2012-2015 Macs on the out-of-tree wl driver still have USB Bluetooth.
run_leaf "Apple Inc." 43a0 0 >/dev/null
[[ -f $conf ]] || fail "a BCM4360 Mac gets the quirk"
pass "a BCM4360 Mac gets the quirk"

run_leaf "Apple Inc." 4331 0 >/dev/null
[[ -f $conf ]] || fail "a BCM4331 Mac gets the quirk"
pass "a BCM4331 Mac gets the quirk"

run_leaf "LENOVO" 43ba 0 >/dev/null
[[ ! -f $conf ]] || fail "non-Apple hardware is left alone"
pass "non-Apple hardware is left alone"

run_leaf "Apple Inc." "" 0 >/dev/null
[[ ! -f $conf ]] || fail "a Mac with no wireless device is left alone"
pass "a Mac with no wireless device is left alone"

run_migration() {
  local vendor="$1" wifi_id="${2:-}" t2="${3:-0}" bt_pcie="${4:-0}"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  : >"$calls"

  WIFI_ID="$wifi_id" T2_HARDWARE="$t2" BT_PCIE="$bt_pcie" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_BRCMFMAC_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    OMARCHY_BTUSB_AUTOSUSPEND_CONF="$conf" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 43ba 0
grep -qx 'options btusb enable_autosuspend=n' "$conf" 2>/dev/null ||
  fail "the migration fixes an install that never got the quirk" "$(ls -R "$test_tmp/etc" 2>&1)"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies it" "$(cat "$calls")"
pass "the migration fixes an install that never got the quirk"

run_migration "Apple Inc." 43ba 0
(( $(grep -c 'enable_autosuspend=n' "$conf") == 1 )) ||
  fail "the migration is idempotent" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "a repaired install is left untouched" "$(cat "$calls")"
pass "the migration is idempotent"

rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 4488 1
[[ ! -e $conf ]] || fail "the migration skips a T2 Mac" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "the migration escalates nothing on a T2 Mac" "$(cat "$calls")"
pass "the migration skips a T2 Mac; its Bluetooth isn't on btusb"

rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 4425 0 1
[[ ! -e $conf ]] || fail "the migration skips an Apple Silicon Mac" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "the migration escalates nothing on an Apple Silicon Mac" "$(cat "$calls")"
pass "the migration skips an Apple Silicon Mac; its Bluetooth isn't on btusb either"

rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 4464 0 1
[[ ! -e $conf ]] || fail "the migration skips a listed Wi-Fi part with PCIe Bluetooth" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "the migration escalates nothing there" "$(cat "$calls")"
pass "the migration skips a Mac with a listed Wi-Fi part but PCIe Bluetooth"

rm -rf "$test_tmp/etc"
run_migration "LENOVO" 43ba 0
[[ ! -e $conf ]] || fail "the migration skips non-Apple hardware" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected hardware" "$(cat "$calls")"
pass "the migration skips hardware without USB-attached Broadcom Bluetooth"
