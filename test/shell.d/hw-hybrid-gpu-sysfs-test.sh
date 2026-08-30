#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

detector="$ROOT/bin/omarchy-hw-hybrid-gpu-sysfs"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Builds a fake sysfs PCI tree from vendor:class pairs.
make_devices() {
  local dir="$1" spec i=0
  shift

  for spec in "$@"; do
    local device="$dir/0000:00:0$i.0"
    mkdir -p "$device"
    echo "${spec%%:*}" > "$device/vendor"
    echo "${spec##*:}" > "$device/class"
    (( i += 1 ))
  done
}

assert_hybrid() {
  local description="$1"
  shift

  local dir
  dir=$(mktemp -d -p "$TMPDIR")
  make_devices "$dir" "$@"

  if OMARCHY_PCI_DEVICES_PATH="$dir" "$detector"; then
    pass "$description"
  else
    fail "$description"
  fi
}

assert_not_hybrid() {
  local description="$1"
  shift

  local dir
  dir=$(mktemp -d -p "$TMPDIR")
  make_devices "$dir" "$@"

  if OMARCHY_PCI_DEVICES_PATH="$dir" "$detector"; then
    fail "$description"
  else
    pass "$description"
  fi
}

assert_hybrid "detects Intel iGPU + NVIDIA dGPU as hybrid" 0x8086:0x030000 0x10de:0x030200
assert_hybrid "detects AMD iGPU + NVIDIA dGPU as hybrid" 0x1002:0x030000 0x10de:0x030200
assert_hybrid "detects Intel + AMD as hybrid" 0x8086:0x030000 0x1002:0x030000

assert_not_hybrid "single NVIDIA GPU is not hybrid" 0x10de:0x030200
assert_not_hybrid "two NVIDIA GPUs are not hybrid" 0x10de:0x030200 0x10de:0x030000
assert_not_hybrid "non-display devices are ignored" 0x8086:0x060000 0x10de:0x0c8000
assert_not_hybrid "empty device tree is not hybrid"
