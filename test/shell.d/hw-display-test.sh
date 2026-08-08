#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

write_backlights() {
  rm -rf "$tmp_dir/backlight"
  mkdir -p "$tmp_dir/backlight"

  local device
  for device in "$@"; do
    mkdir -p "$tmp_dir/backlight/$device"
  done
}

hw_display() {
  OMARCHY_BACKLIGHT_PATH="$tmp_dir/backlight" "$ROOT/bin/omarchy-hw-display"
}

write_backlights intel_backlight
device=$(hw_display)
[[ $device == "intel_backlight" ]] || fail "the only backlight is used" "actual: $device"
pass "the only backlight is used"

write_backlights acpi_video0 amdgpu_bl1
device=$(hw_display)
[[ $device == "amdgpu_bl1" ]] || fail "globbed candidates beat the alphabetical fallback" "actual: $device"
pass "globbed candidates beat the alphabetical fallback"

write_backlights acpi_video0 intel_backlight
device=$(hw_display)
[[ $device == "intel_backlight" ]] || fail "the candidate order is honored" "actual: $device"
pass "the candidate order is honored"

write_backlights nvidia_wmi_ec_backlight
device=$(hw_display)
[[ $device == "nvidia_wmi_ec_backlight" ]] || fail "an unknown backlight falls back to the first device" "actual: $device"
pass "an unknown backlight falls back to the first device"

write_backlights appletb_backlight gmux_backlight
device=$(hw_display)
[[ $device == "gmux_backlight" ]] || fail "a T2 Mac uses gmux instead of the Touch Bar" "actual: $device"
pass "a T2 Mac uses gmux instead of the Touch Bar"

write_backlights appletb_backlight
if hw_display >/dev/null 2>&1; then
  fail "the Touch Bar is never used as the display backlight"
fi
pass "the Touch Bar is never used as the display backlight"

write_backlights acpi_video0 amdgpu_bl0 appletb_backlight gmux_backlight intel_backlight
device=$(hw_display)
[[ $device == "gmux_backlight" ]] || fail "gmux outranks the GPU backlights on dual-GPU Macs" "actual: $device"
pass "gmux outranks the GPU backlights on dual-GPU Macs"

write_backlights
if hw_display >/dev/null 2>&1; then
  fail "no backlight device reports failure"
fi
pass "no backlight device reports failure"
