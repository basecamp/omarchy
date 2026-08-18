#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-brcmfmac-nvram.sh"
all="$ROOT/install/hardware/all.sh"
asset="$ROOT/default/firmware/apple/brcmfmac43602-pcie.txt"
migration="$ROOT/migrations/1786961462.sh"

grep -q 'apple/fix-brcmfmac-nvram.sh' "$all" ||
  fail "the BCM43602 NVRAM leaf runs during hardware setup"
pass "the BCM43602 NVRAM leaf runs during hardware setup"

# The vendored NVRAM is the fix: ccode=0/regrev=1 pin the "world" regulatory
# domain around the firmware's broken country detection (kernel bug 193121).
grep -qx 'ccode=0' "$asset" || fail "the vendored NVRAM keeps ccode=0"
grep -qx 'regrev=1' "$asset" || fail "the vendored NVRAM keeps regrev=1"
grep -q '^macaddr=' "$asset" ||
  fail "the vendored NVRAM carries a macaddr placeholder to substitute"
grep -q '193121' "$asset" || fail "the vendored NVRAM documents its provenance"
grep -qF 'https://bugzilla.kernel.org/attachment.cgi?id=285753' "$asset" ||
  fail "the vendored NVRAM names the exact attachment it was vendored from"
pass "the vendored NVRAM keeps ccode=0/regrev=1 and documents its provenance"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
dest="$test_tmp/firmware/brcm/brcmfmac43602-pcie.txt"
pci_devices="$test_tmp/sys-pci"
mkdir -p "$stub_bin" "$test_tmp/dmi"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Real lspci prints the domain in the BDF only when -D is passed, and /sys uses
# the domain form, so a consumer regressed to parsing plain lspci -nn output
# finds no MAC here and the tests that expect one fail loudly.
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
# match, so a partially-read pipe would kill this stub with SIGPIPE and
# pipefail would read that as "no such hardware" (#6608).
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

# Stubbed rather than run: the real one would write the running user's state.
cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

# The NIC's live address, exposed the way /sys does: under the PCI device's
# net/ directory, named for the bdf the lspci stub reports.
provide_mac() {
  mkdir -p "$pci_devices/0000:03:00.0/net/wlp3s0"
  printf 'aa:bb:cc:dd:ee:ff\n' >"$pci_devices/0000:03:00.0/net/wlp3s0/address"
}

# The leaf reads absolute paths, so redirect them into the sandbox with sed and
# point OMARCHY_PATH at the real tree for the vendored asset. pipefail is on,
# so a partially-read lspci pipe would go silent here the way #6608 did.
run_leaf() {
  local vendor="$1" wifi_id="${2:-}"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"

  local script="$test_tmp/leaf.sh"
  sed -e "s|/sys/class/dmi/id/sys_vendor|$test_tmp/dmi/sys_vendor|g" \
      -e "s|/usr/lib/firmware/brcm|$test_tmp/firmware/brcm|g" \
      -e "s|/sys/bus/pci/devices|$pci_devices|g" \
      "$leaf" >"$script"

  WIFI_ID="$wifi_id" PATH="$stub_bin:$PATH" OMARCHY_PATH="$ROOT" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

# BCM43602 and its single-band variants, on a Mac with no T2 to detect.
for wifi_id in 43ba 43bb 43bc; do
  rm -rf "$test_tmp/firmware" "$pci_devices"
  provide_mac
  run_leaf "Apple Inc." "$wifi_id" >/dev/null
  [[ -f $dest ]] || fail "a Mac with 14e4:$wifi_id gets the NVRAM"
  [[ $(stat -c %a "$dest") == "644" ]] ||
    fail "the NVRAM installs world-readable" "14e4:$wifi_id: $(stat -c %a "$dest")"
  grep -qx 'ccode=0' "$dest" || fail "the installed NVRAM keeps ccode=0" "14e4:$wifi_id"
  grep -qx 'regrev=1' "$dest" || fail "the installed NVRAM keeps regrev=1" "14e4:$wifi_id"
  grep -qx 'macaddr=aa:bb:cc:dd:ee:ff' "$dest" ||
    fail "the installed NVRAM carries the NIC's live MAC" "14e4:$wifi_id: $(grep '^macaddr' "$dest")"
done
pass "every BCM43602 part gets the NVRAM with its live MAC substituted"

# Older Macs report the vendor differently.
rm -rf "$test_tmp/firmware" "$pci_devices"
provide_mac
run_leaf "Apple Computer, Inc." 43ba >/dev/null
[[ -f $dest ]] || fail "the older Apple vendor string is recognized"
pass "the older Apple vendor string is recognized"

# With no MAC discoverable the line goes away entirely; the firmware falls back
# to the OTP address, which is how these NICs already run with no NVRAM.
rm -rf "$test_tmp/firmware" "$pci_devices"
run_leaf "Apple Inc." 43ba >/dev/null
[[ -f $dest ]] || fail "a Mac with no discoverable MAC still gets the NVRAM"
! grep -q '^macaddr=' "$dest" ||
  fail "the macaddr line is stripped when no MAC is discoverable" "$(grep '^macaddr' "$dest")"
grep -qx 'ccode=0' "$dest" || fail "the installed NVRAM keeps ccode=0"
pass "the macaddr line is stripped when no MAC is discoverable"

# BCM4360 Macs run the out-of-tree wl driver, which never reads this file, so
# installing it would only look like the machine had been dealt with.
rm -rf "$test_tmp/firmware" "$pci_devices"
run_leaf "Apple Inc." 43a0 >/dev/null
[[ ! -e $dest ]] || fail "a Mac whose Wi-Fi the wl driver drives is left alone"
pass "a Mac whose Wi-Fi the wl driver drives is left alone"

# Plenty of non-Apple hardware uses brcmfmac and does not share this bug.
rm -rf "$test_tmp/firmware"
run_leaf "LENOVO" 43ba >/dev/null
[[ ! -e $dest ]] || fail "non-Apple hardware is left alone"
pass "non-Apple hardware is left alone"

# An iMac on Ethernet alone has no 14e4 device for the gate to match at all.
run_leaf "Apple Inc." "" >/dev/null
[[ ! -e $dest ]] || fail "a Mac with no wireless device is left alone"
pass "a Mac with no wireless device is left alone"

# An existing file wins, user-placed or package-shipped.
rm -rf "$test_tmp/firmware" "$pci_devices"
provide_mac
mkdir -p "$(dirname "$dest")"
printf 'user-owned\n' >"$dest"
run_leaf "Apple Inc." 43ba >/dev/null
grep -qx 'user-owned' "$dest" ||
  fail "an existing NVRAM is never clobbered" "$(cat "$dest")"
pass "an existing NVRAM is never clobbered"

# Installs that predate the leaf never ran it, so the migration has to reach
# them. It runs as the user under pipefail, the context #6608 was about.
run_migration() {
  local vendor="$1" wifi_id="${2:-}"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  : >"$calls"

  WIFI_ID="$wifi_id" PATH="$stub_bin:$PATH" TEST_LOG="$calls" OMARCHY_PATH="$ROOT" \
    OMARCHY_BRCMFMAC_NVRAM_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    OMARCHY_BRCMFMAC_NVRAM_PCI_DEVICES="$pci_devices" \
    OMARCHY_BRCMFMAC_NVRAM_DEST="$dest" \
    bash -euo pipefail "$migration" >/dev/null
}

# The machine this was written for: a Mac with a BCM43602 and no NVRAM.
rm -rf "$test_tmp/firmware" "$pci_devices"
provide_mac
run_migration "Apple Inc." 43ba
grep -qx 'ccode=0' "$dest" 2>/dev/null ||
  fail "the migration installs the NVRAM" "$(ls -R "$test_tmp/firmware" 2>&1)"
grep -qx 'macaddr=aa:bb:cc:dd:ee:ff' "$dest" ||
  fail "the migration substitutes the live MAC" "$(grep '^macaddr' "$dest")"
# The NVRAM only reaches the firmware when brcmfmac next loads.
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies it" "$(cat "$calls")"
pass "the migration installs the NVRAM and asks for a reboot"

run_migration "Apple Inc." 43ba
[[ ! -s $calls ]] || fail "a repaired install is left untouched" "$(cat "$calls")"
pass "the migration is idempotent"

# No sysfs address for the NIC: the macaddr line is stripped rather than left
# as the donor board's, and the reboot is still requested.
rm -rf "$test_tmp/firmware" "$pci_devices"
run_migration "Apple Inc." 43ba
[[ -f $dest ]] ||
  fail "the migration installs the NVRAM without a discoverable MAC" "$(ls -R "$test_tmp/firmware" 2>&1)"
! grep -q '^macaddr=' "$dest" ||
  fail "the migration strips macaddr when no MAC is discoverable" "$(grep '^macaddr' "$dest")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration still asks for the reboot that applies it" "$(cat "$calls")"
pass "the migration strips macaddr when no MAC is discoverable and still asks for a reboot"

# A file that appeared between leaf and migration -- package update or user --
# outranks the vendored copy.
rm -rf "$test_tmp/firmware"
mkdir -p "$(dirname "$dest")"
printf 'package-shipped\n' >"$dest"
run_migration "Apple Inc." 43ba
grep -qx 'package-shipped' "$dest" ||
  fail "the migration never overwrites an existing NVRAM" "$(cat "$dest")"
[[ ! -s $calls ]] || fail "the migration escalates nothing when the file already exists" "$(cat "$calls")"
pass "the migration never overwrites an existing NVRAM"

rm -rf "$test_tmp/firmware"
run_migration "Apple Inc." 43a0
[[ ! -e $dest ]] || fail "the migration skips a Mac the wl driver drives"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected Macs" "$(cat "$calls")"
pass "the migration skips hardware the NVRAM does not describe"

run_migration "LENOVO" 43ba
[[ ! -e $dest ]] || fail "the migration skips non-Apple hardware"
[[ ! -s $calls ]] || fail "the migration escalates nothing on non-Apple hardware" "$(cat "$calls")"
pass "the migration skips non-Apple hardware"
