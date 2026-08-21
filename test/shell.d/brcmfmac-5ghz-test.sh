#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-brcmfmac-5ghz.sh"
helper="$ROOT/install/hardware/apple/brcmfmac-43602.sh"
nvram="$ROOT/install/hardware/apple/brcmfmac43602-pcie.txt"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1787312531.sh"
manual="$ROOT/manual/44-mac-support.md"

grep -q 'apple/fix-brcmfmac-5ghz.sh' "$all" ||
  fail "the BCM43602 5 GHz NVRAM runs during hardware setup"
grep -q 'apple/fix-brcmfmac-supplicant.sh' "$all" ||
  fail "the 5 GHz leaf does not replace the WPA handshake quirk"
pass "the BCM43602 5 GHz NVRAM runs during setup"

[[ -f $nvram ]] || fail "the calibrated NVRAM is in the tree"
grep -qx 'aa5g=7' "$nvram" || fail "NVRAM enables the 5 GHz antenna chain"
grep -qx 'txchain=7' "$nvram" || fail "NVRAM enables the full TX chain"
grep -qx 'rxchain=7' "$nvram" || fail "NVRAM enables the full RX chain"
grep -qx 'ccode=00' "$nvram" || fail "NVRAM defers channel legality to the host"
grep -qx 'regrev=245' "$nvram" || fail "NVRAM uses the host-deferral revision"
! grep -q '^aa5g=1$' "$nvram" || fail "NVRAM is not the placeholder board file"
pass "the vendored NVRAM has full 5 GHz calibration"

grep -Fq '5 GHz board calibration on BCM43602' "$manual" ||
  fail "Mac support chapter mentions 5 GHz calibration"
pass "Mac support chapter mentions 5 GHz calibration"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
fwdir="$test_tmp/firmware/brcm"
netdir="$test_tmp/net"
mkdir -p "$stub_bin" "$test_tmp/dmi" "$fwdir"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
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

generic() {
  printf '%s\n' "$fwdir/brcmfmac43602-pcie.txt"
}

dmi_file() {
  local vendor=$1 product=$2
  printf '%s\n' "$fwdir/brcmfmac43602-pcie.${vendor}-${product}.txt"
}

invoke_leaf() {
  local wifi_id="${1:-}"
  WIFI_ID="$wifi_id" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_BRCMFMAC_FWDIR="$fwdir" \
    OMARCHY_BRCMFMAC_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    OMARCHY_BRCMFMAC_DMI_PRODUCT="$test_tmp/dmi/product_name" \
    OMARCHY_BRCMFMAC_NETDIR="$netdir" \
    bash -eE -o pipefail -c 'source "$1"' bash "$leaf" </dev/null
}

run_leaf() {
  local vendor=$1 product=$2 wifi_id="${3:-}"
  rm -rf "$fwdir" "$netdir"
  mkdir -p "$fwdir"

  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  printf '%s' "$product" >"$test_tmp/dmi/product_name"

  invoke_leaf "$wifi_id"
}

run_migration() {
  local vendor=$1 product=$2 wifi_id="${3:-}"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  printf '%s' "$product" >"$test_tmp/dmi/product_name"
  : >"$calls"

  WIFI_ID="$wifi_id" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_BRCMFMAC_FWDIR="$fwdir" \
    OMARCHY_BRCMFMAC43602_NVRAM="$nvram" \
    OMARCHY_BRCMFMAC_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    OMARCHY_BRCMFMAC_DMI_PRODUCT="$test_tmp/dmi/product_name" \
    OMARCHY_BRCMFMAC_NETDIR="$netdir" \
    bash -euo pipefail "$migration" >/dev/null
}

run_leaf "Apple Inc." "MacBookPro14,3" 43ba >/dev/null
[[ -f "$(generic)" ]] || fail "a BCM43602 Mac gets the generic NVRAM"
[[ -f "$(dmi_file "Apple Inc." "MacBookPro14,3")" ]] ||
  fail "a BCM43602 Mac gets the DMI-specific NVRAM"
grep -qx 'aa5g=7' "$(generic)" || fail "installed NVRAM enables 5 GHz"
pass "a MacBookPro14,3 with BCM43602 gets both NVRAM names"

run_leaf "Apple Inc." "MacBookPro14,2" 43ba >/dev/null
[[ -f "$(dmi_file "Apple Inc." "MacBookPro14,2")" ]] ||
  fail "MacBookPro14,2 gets its DMI-specific NVRAM"
pass "MacBookPro14,2 gets its DMI-specific NVRAM"

run_leaf "Apple Computer, Inc." "MacBookPro11,4" 43ba >/dev/null
[[ -f "$(dmi_file "Apple Computer, Inc." "MacBookPro11,4")" ]] ||
  fail "the older Apple vendor string is recognized"
pass "the older Apple vendor string is recognized"

# Live interface address is written into macaddr= so we don't change the
# station ID the machine is already using.
rm -rf "$fwdir" "$netdir"
mkdir -p "$fwdir" "$netdir/wlp3s0/wireless"
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
printf '8c:85:90:a3:af:dc\n' >"$netdir/wlp3s0/address"
invoke_leaf 43ba >/dev/null
grep -qx 'macaddr=8c:85:90:a3:af:dc' "$(generic)" ||
  fail "the live Wi-Fi MAC is written into the NVRAM" "$(head "$(generic)")"
grep -qx 'macaddr=8c:85:90:a3:af:dc' "$(dmi_file "Apple Inc." "MacBookPro14,3")" ||
  fail "the DMI-specific NVRAM gets the live MAC"
pass "the live Wi-Fi MAC is written into the NVRAM"

# No wireless interface yet (early install): keep the dump's default MAC.
rm -rf "$netdir"
run_leaf "Apple Inc." "MacBookPro14,3" 43ba >/dev/null
grep -qx 'macaddr=00:90:4c:0d:f4:3e' "$(generic)" ||
  fail "the firmware-default MAC is kept when no interface exists"
pass "the firmware-default MAC is kept when no interface exists"

run_leaf "Apple Inc." "MacBookPro14,3" 43a0 >/dev/null
[[ ! -f "$(generic)" ]] || fail "a Mac whose Wi-Fi brcmfmac does not drive is left alone"
pass "a Mac whose Wi-Fi brcmfmac does not drive is left alone"

run_leaf "Apple Inc." "MacBookPro15,1" 4488 >/dev/null
[[ ! -f "$(generic)" ]] || fail "a T2-era chip is left to apple-bcm-firmware"
pass "a T2-era chip is left to apple-bcm-firmware"

run_leaf "Apple Inc." "MacBookPro14,3" 43bb >/dev/null
[[ ! -f "$(generic)" ]] || fail "the 2 GHz-only BCM43602 variant is left alone"
pass "the 2 GHz-only BCM43602 variant is left alone"

run_leaf "LENOVO" "ThinkPad" 43ba >/dev/null
[[ ! -f "$(generic)" ]] || fail "non-Apple hardware is left alone"
pass "non-Apple hardware is left alone"

run_leaf "Apple Inc." "MacBookPro14,3" >/dev/null
[[ ! -f "$(generic)" ]] || fail "a Mac with no wireless device is left alone"
pass "a Mac with no wireless device is left alone"

# Incomplete placeholder already on disk is replaced.
mkdir -p "$fwdir"
printf 'aa5g=1\ntxchain=1\nccode=ALL\n' >"$(generic)"
run_leaf "Apple Inc." "MacBookPro14,3" 43ba >/dev/null
grep -qx 'aa5g=7' "$(generic)" || fail "a placeholder NVRAM is replaced"
pass "a placeholder NVRAM is replaced"

# Complete files are left alone, including a user-set MAC.
mkdir -p "$fwdir"
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
cp "$nvram" "$(generic)"
cp "$nvram" "$(dmi_file "Apple Inc." "MacBookPro14,3")"
sed -i 's/^macaddr=.*/macaddr=de:ad:be:ef:00:01/' "$(generic)"
sed -i 's/^macaddr=.*/macaddr=de:ad:be:ef:00:01/' "$(dmi_file "Apple Inc." "MacBookPro14,3")"
: >"$calls"
invoke_leaf 43ba >/dev/null
grep -qx 'macaddr=de:ad:be:ef:00:01' "$(generic)" ||
  fail "a complete NVRAM is not overwritten"
[[ ! -s $calls ]] || fail "a complete install does not escalate" "$(cat "$calls")"
pass "a complete NVRAM is not overwritten"

rm -rf "$fwdir" "$netdir"
mkdir -p "$fwdir"
run_migration "Apple Inc." "MacBookPro14,3" 43ba
[[ -f "$(generic)" ]] || fail "the migration installs NVRAM on an existing Mac"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies it" "$(cat "$calls")"
pass "the migration installs NVRAM and asks for a reboot"

run_migration "Apple Inc." "MacBookPro14,3" 43ba
[[ ! -s $calls ]] || fail "the migration is idempotent" "$(cat "$calls")"
pass "the migration is idempotent"

rm -rf "$fwdir"
run_migration "LENOVO" "ThinkPad" 43ba
[[ ! -e "$(generic)" ]] || fail "the migration skips non-Apple hardware"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected machines" "$(cat "$calls")"
pass "the migration skips non-Apple hardware"

# Helper is sourced by install leaves; leaking nullglob would change later globbing.
# shellcheck source=../../install/hardware/apple/brcmfmac-43602.sh
OMARCHY_INSTALL="$ROOT/install" source "$helper"
OMARCHY_BRCMFMAC_NETDIR="$test_tmp/empty-net" brcmfmac43602_wifi_mac || true
shopt -q nullglob && fail "applying NVRAM does not leave nullglob on"
pass "applying NVRAM does not leave nullglob on"
