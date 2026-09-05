#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Each argument is a PCI device as "vendor:device:class", in sysfs's own format.
write_pci_devices() {
  rm -rf "$tmp_dir/devices"
  mkdir -p "$tmp_dir/devices"

  local index=0
  local spec
  for spec in "$@"; do
    local slot
    slot=$(printf '0000:%02x:00.0' "$index")
    mkdir -p "$tmp_dir/devices/$slot"
    printf '%s\n' "${spec%%:*}" >"$tmp_dir/devices/$slot/vendor"
    printf '%s\n' "$(cut -d: -f2 <<<"$spec")" >"$tmp_dir/devices/$slot/device"
    printf '%s\n' "${spec##*:}" >"$tmp_dir/devices/$slot/class"
    index=$((index + 1))
  done
}

vaapi_driver() {
  OMARCHY_PCI_DEVICES_PATH="$tmp_dir/devices" "$ROOT/bin/omarchy-hw-intel-vaapi-driver"
}

assert_driver() {
  local description="$1"
  local expected="$2"
  local actual=""
  local status=0

  actual=$(vaapi_driver) || status=$?

  if [[ $expected == "none" ]]; then
    [[ $status -ne 0 && -z $actual ]] ||
      fail "$description" "expected no Intel VAAPI package, got status=$status output=${actual@Q}"
    pass "$description"
    return
  fi

  [[ $status -eq 0 && $actual == "$expected" ]] ||
    fail "$description" "expected $expected, got status=$status output=${actual@Q}"
  pass "$description"
}

# NVIDIA GM204M [GTX 970M] only.
write_pci_devices 0x10de:0x13d8:0x030200
assert_driver "a machine without an Intel GPU prints nothing" none

# Intel Haswell GT2 [8086:0416], the iGPU from issue #2706 / this hybrid laptop.
# lspci name is "4th Gen Core Processor Integrated Graphics Controller" — no
# "HD Graphics" token for the old regex to match.
write_pci_devices 0x8086:0x0416:0x030000
assert_driver "Haswell uses libva-intel-driver" libva-intel-driver

# Same Haswell iGPU next to the 970M: still the Intel package, not NVIDIA.
write_pci_devices 0x8086:0x0416:0x030000 0x10de:0x13d8:0x030200
assert_driver "a hybrid Haswell+NVIDIA laptop uses libva-intel-driver" libva-intel-driver

# Ivy Bridge HD Graphics 4000.
write_pci_devices 0x8086:0x0166:0x030000
assert_driver "Ivy Bridge uses libva-intel-driver" libva-intel-driver

# Broadwell HD Graphics 5500, first generation for intel-media-driver.
write_pci_devices 0x8086:0x1616:0x030000
assert_driver "Broadwell uses intel-media-driver" intel-media-driver

# Skylake HD Graphics 530.
write_pci_devices 0x8086:0x1912:0x030000
assert_driver "Skylake uses intel-media-driver" intel-media-driver

# Alder Lake-P [Iris Xe].
write_pci_devices 0x8086:0x46a6:0x030000
assert_driver "Iris Xe uses intel-media-driver" intel-media-driver

# GM45 / Mobile 4 Series. ID sits above 0x1600; a bare cutoff would pick iHD.
write_pci_devices 0x8086:0x2a42:0x030000
assert_driver "GM45 uses libva-intel-driver" libva-intel-driver

# Braswell / CherryView. Same trap: 0x22b1 > 0x1600 but iHD does not support it.
write_pci_devices 0x8086:0x22b1:0x030000
assert_driver "Braswell uses libva-intel-driver" libva-intel-driver

# 4 Series desktop (G41). First gens in i965's PCI table, with GM45.
write_pci_devices 0x8086:0x2e32:0x030000
assert_driver "4 Series uses libva-intel-driver" libva-intel-driver

# Broxton borrows Haswell's 0x0axx prefix but is Gen9. This pins the upper bound
# of the Haswell block, which nothing else would catch if it widened to 0x0aff.
write_pci_devices 0x8086:0x0a84:0x030000
assert_driver "Broxton uses intel-media-driver" intel-media-driver

# Pre-GM45 chipset graphics: neither package can initialize.
write_pci_devices 0x8086:0x27a2:0x030000
assert_driver "945GM has no VAAPI package" none

write_pci_devices 0x8086:0x2a02:0x030000
assert_driver "GM965 has no VAAPI package" none

write_pci_devices 0x8086:0x29a2:0x030000
assert_driver "G965 has no VAAPI package" none

write_pci_devices 0x8086:0xa011:0x030000
assert_driver "Pineview has no VAAPI package" none

write_pci_devices 0x8086:0x4108:0x030000
assert_driver "Atom E6xx has no VAAPI package" none

write_pci_devices 0x8086:0x8108:0x030000
assert_driver "Poulsbo has no VAAPI package" none

# Haswell iGPU plus a later Intel GPU: both packages. The display node is
# still the i965 iGPU; iHD-only would recreate #2706 on a Haswell+Arc box.
write_pci_devices 0x8086:0x0416:0x030000 0x8086:0x56a5:0x030000
assert_driver "Haswell plus Arc installs both Intel VAAPI packages" $'intel-media-driver\nlibva-intel-driver'

write_pci_devices 0x8086:0x56a5:0x030000 0x8086:0x0416:0x030000
assert_driver "Arc listed before Haswell still installs both packages" $'intel-media-driver\nlibva-intel-driver'

write_pci_devices 0x8086:0x0416:0x030000 0x8086:0x7d55:0x030000
assert_driver "Haswell plus Meteor Lake installs both Intel VAAPI packages" $'intel-media-driver\nlibva-intel-driver'

# Two devices in the same bucket stay a single package.
write_pci_devices 0x8086:0x1616:0x030000 0x8086:0x56a5:0x030000
assert_driver "two iHD GPUs print intel-media-driver once" intel-media-driver

write_pci_devices 0x8086:0x0416:0x030000 0x8086:0x0166:0x030000
assert_driver "two i965 GPUs print libva-intel-driver once" libva-intel-driver

# Intel HD Audio function is not a GPU.
write_pci_devices 0x8086:0x0c0c:0x040300
assert_driver "a non-display Intel function is not a GPU" none

write_pci_devices
assert_driver "a machine with no PCI devices prints nothing" none

# Missing or unreadable device must skip, not silently select i965.
write_pci_devices 0x8086:0x0416:0x030000
rm -f "$tmp_dir/devices/0000:00:00.0/device"
assert_driver "a missing sysfs device file is a skip" none

write_pci_devices 0x8086:0x0416:0x030000
: >"$tmp_dir/devices/0000:00:00.0/device"
assert_driver "an empty sysfs device file is a skip" none

write_pci_devices 0x8086:0x0416:0x030000
printf '%s\n' "not-a-pci-id" >"$tmp_dir/devices/0000:00:00.0/device"
assert_driver "a non-hex sysfs device file is a skip" none
