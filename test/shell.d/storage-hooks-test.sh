#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

hooks_conf="$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf"

# Stub findmnt and lsblk so the storage detection is deterministic regardless
# of the filesystem the test runner lives on. The stubs are installed into a
# directory put at the front of PATH, and the hook config is sourced with the
# vconsole block pinned to a Latin layout.
fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/findmnt" <<'STUB'
#!/bin/bash
# args used: findmnt -no SOURCE /   and   findmnt -no FSTYPE /
if [[ $1 == "-no" && $2 == "SOURCE" ]]; then
  printf '%s\n' "$OMARCHY_TEST_ROOT_DEVICE"
elif [[ $1 == "-no" && $2 == "FSTYPE" ]]; then
  printf '%s\n' "$OMARCHY_TEST_ROOT_FSTYPE"
else
  exit 0
fi
STUB
chmod +x "$fake_bin/findmnt"

cat >"$fake_bin/lsblk" <<'STUB'
#!/bin/bash
# lsblk -rno TYPE <device>
printf '%s\n' "$OMARCHY_TEST_ROOT_STACK"
STUB
chmod +x "$fake_bin/lsblk"

resolved_hooks() {
  OMARCHY_PCI_DEVICES_PATH="$tmp_dir/devices" \
  FAKE_BIN_OVERRIDE=1 \
  PATH="$fake_bin:$PATH" \
  bash -uc "
    FILES=()
    XKBLAYOUT=us
    source '$hooks_conf'
    echo \"\${HOOKS[*]}\"
  "
}

required_hooks() {
  local description="$1" device="$2" fstype="$3" stack="$4"
  local expected="base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block"
  local actual

  case "$stack" in
    *lvm*) expected+=" lvm2" ;;
  esac
  case "$stack" in
    *crypt*) expected+=" encrypt" ;;
  esac
  [[ $fstype == "btrfs" ]] && expected+=" btrfs-overlayfs"
  expected+=" filesystems fsck"

  actual=$(FAKE_OMARCHY_ROOT_STACK="$stack" FAKE_OMARCHY_ROOT="$device" OMARCHY_TEST_ROOT_DEVICE="$device" OMARCHY_TEST_ROOT_FSTYPE="$fstype" OMARCHY_TEST_ROOT_STACK="$stack" resolved_hooks)
  [[ $actual == "$expected" ]] ||
    fail "$description" "expected: $expected"$'\n'"actual:   $actual"
  pass "$description"
}

mkdir -p "$tmp_dir/devices"

required_hooks "plain btrfs root keeps only btrfs-overlayfs" \
  "/dev/nvme0n1p2" "btrfs" "part"

required_hooks "LVM root gains the lvm2 hook" \
  "/dev/mapper/vg0-root" "ext4" "lvm"

required_hooks "LUKS root gains the encrypt hook" \
  "/dev/mapper/cryptroot" "ext4" "crypt"

required_hooks "LVM-on-LUKS root gains lvm2 and encrypt hooks" \
  "/dev/mapper/vg0-root" "ext4" $'lvm\ncrypt'

required_hooks "LVM root on btrfs gains lvm2 and btrfs-overlayfs" \
  "/dev/mapper/vg0-root" "btrfs" "lvm"

required_hooks "plain ext4 root adds neither storage hook" \
  "/dev/sda2" "ext4" "part"