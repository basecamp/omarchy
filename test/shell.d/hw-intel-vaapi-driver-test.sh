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

  if [[ $expected == none ]]; then
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

# Intel HD Audio function is not a GPU.
write_pci_devices 0x8086:0x0c0c:0x040300
assert_driver "a non-display Intel function is not a GPU" none

write_pci_devices
assert_driver "a machine with no PCI devices prints nothing" none
