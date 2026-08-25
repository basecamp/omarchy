#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Each argument is a PCI device as "vendor:class", in sysfs's own format.
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
    printf '%s\n' "${spec##*:}" >"$tmp_dir/devices/$slot/class"
    index=$((index + 1))
  done
}

assert_nvidia_only() {
  local description="$1" expected="$2"

  local actual=no
  OMARCHY_PCI_DEVICES_PATH="$tmp_dir/devices" "$ROOT/bin/omarchy-hw-nvidia-only-display" && actual=yes

  [[ $actual == "$expected" ]] || fail "$description" "expected $expected, got $actual"
  pass "$description"
}

write_pci_devices 0x10de:0x030000
assert_nvidia_only "a lone NVIDIA GPU owns every display controller" yes

# The GPU's own audio function is not a display controller.
write_pci_devices 0x10de:0x030000 0x10de:0x040300
assert_nvidia_only "a non-display NVIDIA function does not change the answer" yes

write_pci_devices 0x8086:0x030000 0x10de:0x030200
assert_nvidia_only "an Intel iGPU beside the NVIDIA GPU makes it hybrid" no

write_pci_devices 0x1002:0x030000 0x10de:0x030200
assert_nvidia_only "an AMD iGPU beside the NVIDIA GPU makes it hybrid" no

write_pci_devices 0x1002:0x030000
assert_nvidia_only "a machine without NVIDIA is not NVIDIA-only" no

write_pci_devices
assert_nvidia_only "a machine with no PCI devices is not NVIDIA-only" no

# A device whose class cannot be read could be another GPU, so the helper
# refuses to claim NVIDIA-only.
write_pci_devices 0x10de:0x030000 0x8086:0x030000
chmod 000 "$tmp_dir/devices/0000:01:00.0/class"
if [[ $(id -u) -ne 0 ]]; then
  assert_nvidia_only "an unreadable device keeps the answer conservative" no
fi
