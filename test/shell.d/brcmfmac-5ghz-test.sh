#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-brcmfmac-5ghz.sh"
nvram="$ROOT/default/firmware/apple/brcmfmac43602-pcie.txt"
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
grep -q '290569' "$nvram" || fail "NVRAM documents its bugzilla attachment"
grep -qF 'https://bugzilla.kernel.org/attachment.cgi?id=290569' "$nvram" ||
  fail "NVRAM names the exact attachment it was vendored from"
! grep -q '^aa5g=1$' "$nvram" || fail "NVRAM is not the placeholder board file"
pass "the vendored NVRAM has full 5 GHz calibration and provenance"

grep -Fq '5 GHz board calibration on 2017 Touch Bar MacBook Pros' "$manual" ||
  fail "Mac support chapter mentions 5 GHz calibration"
pass "Mac support chapter mentions 5 GHz calibration"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
fwdir="$test_tmp/firmware/updates/brcm"
packaged="$test_tmp/firmware/brcm"
pci_devices="$test_tmp/sys-pci"
mkdir -p "$stub_bin" "$test_tmp/dmi"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Real lspci prints the domain in the BDF only when -D is passed, and /sys uses
# the domain form, so a consumer that parses plain lspci -nn finds no MAC.
domain=0
for arg in "$@"; do
  if [[ $arg == -*D* ]]; then
    domain=1
  fi
done

if (( domain == 1 )); then
  wifi_bdf=0000:03:00.0
  filler_bdf=0000:02:00.0
else
  wifi_bdf=03:00.0
  filler_bdf=02:00.0
fi

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
if [[ -n ${WIFI_ID:-} ]]; then
  echo "$wifi_bdf Network controller [0280]: Broadcom Inc. Wireless [14e4:$WIFI_ID]"
fi
for _ in {1..4096}; do
  echo "$filler_bdf Host bridge [0600]: Filler Device [ffff:0000]"
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

provide_mac() {
  mkdir -p "$pci_devices/0000:03:00.0/net/wlp3s0"
  printf 'aa:bb:cc:dd:ee:ff\n' >"$pci_devices/0000:03:00.0/net/wlp3s0/address"
}

# The wiphy's permanent address, as opposed to the netdev's current one.
provide_perm_mac() {
  local mac=$1
  mkdir -p "$pci_devices/0000:03:00.0/ieee80211/phy0"
  printf '%s\n' "$mac" >"$pci_devices/0000:03:00.0/ieee80211/phy0/macaddress"
}

# Production run_logged uses bash -eE with no pipefail.
invoke_leaf() {
  local wifi_id="${1:-}"
  WIFI_ID="$wifi_id" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_BRCMFMAC_FWDIR="$fwdir" \
    OMARCHY_BRCMFMAC_PACKAGED_FWDIR="$packaged" \
    OMARCHY_BRCMFMAC_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    OMARCHY_BRCMFMAC_DMI_PRODUCT="$test_tmp/dmi/product_name" \
    OMARCHY_BRCMFMAC_PCI_DEVICES="$pci_devices" \
    bash -eE -c 'source "$1"' bash "$leaf" </dev/null
}

run_leaf() {
  local vendor=$1 product=$2 wifi_id="${3:-}"
  rm -rf "$fwdir" "$packaged" "$pci_devices"
  mkdir -p "$fwdir" "$packaged"
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
    OMARCHY_PATH="$ROOT" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_BRCMFMAC_FWDIR="$fwdir" \
    OMARCHY_BRCMFMAC_PACKAGED_FWDIR="$packaged" \
    OMARCHY_BRCMFMAC43602_NVRAM="$nvram" \
    OMARCHY_BRCMFMAC_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    OMARCHY_BRCMFMAC_DMI_PRODUCT="$test_tmp/dmi/product_name" \
    OMARCHY_BRCMFMAC_PCI_DEVICES="$pci_devices" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_mac
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
invoke_leaf 43ba >/dev/null
[[ -f "$(generic)" ]] || fail "a MacBookPro14,3 gets the generic NVRAM"
[[ -f "$(dmi_file "Apple Inc." "MacBookPro14,3")" ]] ||
  fail "a MacBookPro14,3 gets the DMI-specific NVRAM"
grep -qx 'aa5g=7' "$(generic)" || fail "installed NVRAM enables 5 GHz"
grep -qx 'macaddr=aa:bb:cc:dd:ee:ff' "$(generic)" ||
  fail "the installed NVRAM carries the NIC's live MAC" "$(grep '^macaddr' "$(generic)")"
grep -qx 'macaddr=aa:bb:cc:dd:ee:ff' "$(dmi_file "Apple Inc." "MacBookPro14,3")" ||
  fail "the DMI-specific NVRAM gets the live MAC"
pass "a MacBookPro14,3 with BCM43602 gets both NVRAM names and the live MAC"

rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_mac
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,2" >"$test_tmp/dmi/product_name"
invoke_leaf 43ba >/dev/null
[[ -f "$(dmi_file "Apple Inc." "MacBookPro14,2")" ]] ||
  fail "MacBookPro14,2 gets its DMI-specific NVRAM"
pass "MacBookPro14,2 gets its DMI-specific NVRAM"

rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_mac
printf '%s' "Apple Computer, Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
invoke_leaf 43ba >/dev/null
[[ -f "$(dmi_file "Apple Computer, Inc." "MacBookPro14,3")" ]] ||
  fail "the older Apple vendor string is recognized"
pass "the older Apple vendor string is recognized"

# NetworkManager randomises the netdev address while scanning; the wiphy's
# permanent address is the one to persist.
rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_perm_mac 11:22:33:44:55:66
mkdir -p "$pci_devices/0000:03:00.0/net/wlp3s0"
printf 'f2:11:22:33:44:55\n' >"$pci_devices/0000:03:00.0/net/wlp3s0/address"
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
invoke_leaf 43ba >/dev/null
grep -qx 'macaddr=11:22:33:44:55:66' "$(generic)" ||
  fail "the permanent address wins over a randomised netdev address" "$(grep '^macaddr' "$(generic)")"
pass "the permanent address wins over a randomised netdev address"

# A card with no usable OTP boots on Broadcom's 00:90:4c placeholder and
# reports it as its own address; persisting that would share it across
# machines.
rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_perm_mac 00:90:4c:0d:f4:3e
mkdir -p "$pci_devices/0000:03:00.0/net/wlp3s0"
printf '00:90:4C:0D:F4:3E\n' >"$pci_devices/0000:03:00.0/net/wlp3s0/address"
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
invoke_leaf 43ba >/dev/null
[[ -f "$(generic)" ]] || fail "a card on the placeholder address still gets the NVRAM"
! grep -q '^macaddr=' "$(generic)" ||
  fail "the Broadcom placeholder address is never persisted" "$(grep '^macaddr' "$(generic)")"
pass "the Broadcom placeholder address is never persisted"

# No MAC discoverable: drop the line rather than shipping the donor address.
rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
invoke_leaf 43ba >/dev/null
[[ -f "$(generic)" ]] || fail "a Mac with no discoverable MAC still gets the NVRAM"
! grep -q '^macaddr=' "$(generic)" ||
  fail "the macaddr line is stripped when no MAC is discoverable" "$(grep '^macaddr' "$(generic)")"
pass "the macaddr line is stripped when no MAC is discoverable"

run_leaf "Apple Inc." "MacBookPro14,3" 43a0 >/dev/null
[[ ! -f "$(generic)" ]] || fail "a Mac whose Wi-Fi brcmfmac does not drive is left alone"
pass "a Mac whose Wi-Fi brcmfmac does not drive is left alone"

run_leaf "Apple Inc." "MacBookPro15,1" 4488 >/dev/null
[[ ! -f "$(generic)" ]] || fail "a T2-era chip is left to apple-bcm-firmware"
pass "a T2-era chip is left to apple-bcm-firmware"

run_leaf "Apple Inc." "MacBookPro14,3" 43bb >/dev/null
[[ ! -f "$(generic)" ]] || fail "the 2 GHz-only BCM43602 variant is left alone"
pass "the 2 GHz-only BCM43602 variant is left alone"

# Same PCI ID, different board; this dump has a report of unusable range there.
run_leaf "Apple Inc." "MacBookPro13,3" 43ba >/dev/null
[[ ! -f "$(generic)" ]] || fail "MacBookPro13,3 is outside the model gate"
pass "MacBookPro13,3 is outside the model gate"

run_leaf "Apple Inc." "MacBookPro11,4" 43ba >/dev/null
[[ ! -f "$(generic)" ]] || fail "a 2015 BCM43602 Mac is outside the model gate"
pass "a 2015 BCM43602 Mac is outside the model gate"

run_leaf "LENOVO" "ThinkPad" 43ba >/dev/null
[[ ! -f "$(generic)" ]] || fail "non-Apple hardware is left alone"
pass "non-Apple hardware is left alone"

run_leaf "Apple Inc." "MacBookPro14,3" >/dev/null
[[ ! -f "$(generic)" ]] || fail "a Mac with no wireless device is left alone"
pass "a Mac with no wireless device is left alone"

# An existing file wins, user-placed or package-shipped. invoke_leaf, not
# run_leaf: run_leaf wipes fwdir first, which made the previous clobber
# assertion vacuous.
rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_mac
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
printf 'user-owned\n' >"$(generic)"
invoke_leaf 43ba >/dev/null
grep -qx 'user-owned' "$(generic)" ||
  fail "an existing NVRAM is never clobbered" "$(cat "$(generic)")"
pass "an existing NVRAM is never clobbered"

# A packaged linux-firmware board file also outranks this copy.
rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_mac
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
printf 'package-shipped\n' >"$packaged/brcmfmac43602-pcie.txt"
invoke_leaf 43ba >/dev/null
[[ ! -e "$(generic)" ]] || fail "a packaged NVRAM prevents writing the override"
pass "a packaged NVRAM prevents writing the override"

# Arch ships every firmware file zstd-compressed, so this is the name a real
# linux-firmware board file would arrive under.
rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_mac
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
printf 'package-shipped\n' >"$packaged/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,3.txt.zst"
invoke_leaf 43ba >/dev/null
[[ ! -e "$(generic)" ]] || fail "a compressed packaged NVRAM prevents writing the override"
pass "a compressed packaged NVRAM prevents writing the override"

# A failed install must not look like success. Stub install(1) to truncate its
# destination and then fail, the shape ENOSPC takes, after the gate has
# matched, so the leaf's set -e surfaces the error and nothing partial is left
# under a name the driver loads or the skip guard honours.
rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_mac
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
cat >"$stub_bin/install" <<'SH'
#!/bin/bash
: >"${@: -1}"
exit 1
SH
chmod +x "$stub_bin/install"
if invoke_leaf 43ba >/dev/null 2>&1; then
  fail "a failed install does not look like success"
fi
rm -f "$stub_bin/install"
[[ ! -e "$(generic)" ]] || fail "a failed install leaves no dest file"
[[ -z $(ls -A "$fwdir") ]] || fail "a failed install leaves nothing behind" "$(ls -A "$fwdir")"
pass "a failed install does not look like success"

# The generic and DMI-specific names land together or not at all: one file on
# disk would satisfy the skip guard while the migration's reboot prompt is lost.
rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_mac
printf '%s' "Apple Inc." >"$test_tmp/dmi/sys_vendor"
printf '%s' "MacBookPro14,3" >"$test_tmp/dmi/product_name"
cat >"$stub_bin/install" <<SH
#!/bin/bash
if [[ -e "$test_tmp/install-once" ]]; then
  exit 1
fi
touch "$test_tmp/install-once"
exec /usr/bin/install "\$@"
SH
chmod +x "$stub_bin/install"
if invoke_leaf 43ba >/dev/null 2>&1; then
  fail "a half-written NVRAM pair does not look like success"
fi
rm -f "$stub_bin/install" "$test_tmp/install-once"
[[ -z $(ls -A "$fwdir") ]] || fail "a half-written NVRAM pair is rolled back" "$(ls -A "$fwdir")"
pass "a half-written NVRAM pair is rolled back"

rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_mac
run_migration "Apple Inc." "MacBookPro14,3" 43ba
[[ -f "$(generic)" ]] || fail "the migration installs NVRAM on an existing Mac"
grep -qx 'macaddr=aa:bb:cc:dd:ee:ff' "$(generic)" ||
  fail "the migration substitutes the live MAC" "$(grep '^macaddr' "$(generic)")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies it" "$(cat "$calls")"
pass "the migration installs NVRAM and asks for a reboot"

run_migration "Apple Inc." "MacBookPro14,3" 43ba
[[ ! -s $calls ]] || fail "the migration is idempotent" "$(cat "$calls")"
pass "the migration is idempotent"

rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
run_migration "Apple Inc." "MacBookPro14,3" 43ba
[[ -f "$(generic)" ]] || fail "the migration installs NVRAM without a discoverable MAC"
! grep -q '^macaddr=' "$(generic)" ||
  fail "the migration strips macaddr when no MAC is discoverable" "$(grep '^macaddr' "$(generic)")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration still asks for a reboot without a MAC" "$(cat "$calls")"
pass "the migration strips macaddr when no MAC is discoverable"

rm -rf "$fwdir" "$packaged"
mkdir -p "$fwdir" "$packaged"
printf 'already-there\n' >"$(generic)"
run_migration "Apple Inc." "MacBookPro14,3" 43ba
grep -qx 'already-there' "$(generic)" ||
  fail "the migration never overwrites an existing NVRAM" "$(cat "$(generic)")"
[[ ! -s $calls ]] || fail "the migration escalates nothing when the file already exists" "$(cat "$calls")"
pass "the migration never overwrites an existing NVRAM"

rm -rf "$fwdir" "$packaged"
run_migration "Apple Inc." "MacBookPro13,3" 43ba
[[ ! -e "$(generic)" ]] || fail "the migration skips MacBookPro13,3"
[[ ! -s $calls ]] || fail "the migration escalates nothing on excluded models" "$(cat "$calls")"
pass "the migration skips MacBookPro13,3"

rm -rf "$fwdir"
run_migration "LENOVO" "ThinkPad" 43ba
[[ ! -e "$(generic)" ]] || fail "the migration skips non-Apple hardware"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected machines" "$(cat "$calls")"
pass "the migration skips non-Apple hardware"

# A failed migration install must not mark the migration done via reboot-required,
# and the rerun omarchy-migrate then makes must do the work it skipped.
rm -rf "$fwdir" "$packaged" "$pci_devices"
mkdir -p "$fwdir" "$packaged"
provide_mac
cat >"$stub_bin/install" <<'SH'
#!/bin/bash
: >"${@: -1}"
exit 1
SH
chmod +x "$stub_bin/install"
if run_migration "Apple Inc." "MacBookPro14,3" 43ba; then
  fail "a failed migration install does not look like success"
fi
rm -f "$stub_bin/install"
grep -q 'omarchy-state' "$calls" &&
  fail "a failed migration does not ask for a reboot" "$(cat "$calls")"
pass "a failed migration install does not look like success"

run_migration "Apple Inc." "MacBookPro14,3" 43ba
grep -qx 'aa5g=7' "$(generic)" ||
  fail "the rerun after a failed migration installs the NVRAM" "$(ls -A "$fwdir")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the rerun after a failed migration asks for the reboot" "$(cat "$calls")"
pass "the rerun after a failed migration installs and asks for the reboot"
