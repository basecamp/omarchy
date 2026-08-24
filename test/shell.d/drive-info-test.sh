#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"

# A machine with an encrypted root, which is the topology that broke this:
#
#   sda            disk   Samsung SSD 870 EVO 1TB
#   ├─sda1         part   vfat  /boot
#   └─sda2         part   crypto_LUKS
#     └─root       crypt  ext4  /
#
# The mapping under sda2 is the whole difference: without it the PKNAME listing
# ends on the disk, which is why unencrypted drives happened to work.
cat >"$tmp_dir/bin/lsblk" <<'STUB'
#!/bin/bash

dev=${*: -1}
name=${dev#/dev/}
opts=$*

parent_of() {
  case "$1" in
    sda1|sda2) printf 'sda\n' ;;
    root) printf 'sda2\n' ;;
    *) : ;;
  esac
}

# -d limits the query to the device itself; without it lsblk walks descendants.
if [[ $opts == *-dno\ PKNAME* ]]; then
  parent_of "$name"
elif [[ $opts == *-no\ PKNAME* ]]; then
  case "$name" in
    sda) printf '\nsda\nsda\nsda2\n' ;;
    sda2) printf 'sda\nsda2\n' ;;
    sda1) printf 'sda\n' ;;
    root) printf 'sda2\n' ;;
  esac
elif [[ $opts == *-dno\ SIZE* ]]; then
  case "$name" in
    sda) printf '931.5G\n' ;;
    sda1) printf '2G\n' ;;
    sda2) printf '929.5G\n' ;;
    root) printf '929.5G\n' ;;
  esac
elif [[ $opts == *-dno\ VENDOR* ]]; then
  # Only the disk carries these; partitions and mappings report nothing.
  [[ $name == sda ]] && printf 'ATA     \n'
elif [[ $opts == *-dno\ MODEL* ]]; then
  [[ $name == sda ]] && printf 'Samsung SSD 870 EVO 1TB\n'
elif [[ $opts == *TYPE,NAME,FSTYPE,MOUNTPOINT* ]]; then
  case "$name" in
    sda)
      printf 'disk sda  \n'
      printf 'part sda1 vfat /boot\n'
      printf 'part sda2 crypto_LUKS \n'
      printf 'crypt root ext4 /\n'
      ;;
    sda2)
      printf 'part sda2 crypto_LUKS \n'
      printf 'crypt root ext4 /\n'
      ;;
  esac
fi
STUB
chmod +x "$tmp_dir/bin/lsblk"

drive_info() {
  PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-drive-info" "$1"
}

# The disk itself: the model must survive the crypt layer further down.
out=$(drive_info /dev/sda)
[[ $out == *"Samsung SSD 870 EVO 1TB"* ]] ||
  fail "drive info keeps the model when a crypt layer hangs below the disk" "$out"
[[ $out == *"vfat(/boot)"* && $out == *"crypto_LUKS"* ]] ||
  fail "drive info summarises every partition of the disk" "$out"
pass "drive info reports a disk with an encrypted partition"

# A partition resolves up to its disk, not to itself.
out=$(drive_info /dev/sda2)
[[ $out == *"Samsung SSD 870 EVO 1TB"* ]] ||
  fail "drive info resolves a partition to its disk" "$out"
[[ $out == *"(929.5G)"* ]] ||
  fail "drive info reports the size of the device asked about, not the disk" "$out"
pass "drive info resolves a partition up to its disk"

# The mapping is two levels down; one hop up is still a partition.
out=$(drive_info /dev/root)
[[ $out == *"Samsung SSD 870 EVO 1TB"* ]] ||
  fail "drive info walks up through a crypt mapping to the disk" "$out"
pass "drive info walks up through a nested mapping"

# ATA is a prefix of the model string, so it must not be printed twice.
out=$(drive_info /dev/sda)
[[ $out != *"ATA ATA"* ]] || fail "drive info does not duplicate the vendor" "$out"
pass "drive info does not duplicate a vendor already in the model"
