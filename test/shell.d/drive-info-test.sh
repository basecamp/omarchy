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
# happens to end on the disk, which is why unencrypted drives worked by luck.
cat >"$tmp_dir/bin/lsblk" <<'STUB'
#!/bin/bash

dev=${*: -1}
name=${dev#/dev/}
opts=$*

parent_of() {
  case "$1" in
    sda1|sda2) printf 'sda\n' ;;
    root) printf 'sda2\n' ;;
    sdb1) printf 'sdb\n' ;;
    *) : ;;
  esac
}

if [[ $opts == *-no\ PKNAME* ]]; then
  # Without -d, lsblk lists the device and every descendant, each with the
  # parent name of that row. The device itself has no parent, so the first
  # non-empty line is the parent of the device asked about.
  case "$name" in
    sda) printf '\nsda\nsda\nsda2\n' ;;
    sda1) printf 'sda\n' ;;
    sda2) printf 'sda\nsda2\n' ;;
    root) printf 'sda2\n' ;;
    sdb) printf '\nsdb\n' ;;
    sdb1) printf 'sdb\n' ;;
  esac
elif [[ $opts == *-dno\ SIZE* ]]; then
  case "$name" in
    sda) printf '931.5G\n' ;;
    sda1) printf '2G\n' ;;
    sda2) printf '929.5G\n' ;;
    root) printf '929.5G\n' ;;
    sdb) printf '931.5G\n' ;;
    sdb1) printf '931.5G\n' ;;
  esac
elif [[ $opts == *-dno\ VENDOR* ]]; then
  # Only the disk carries these; partitions and mappings report nothing.
  case "$name" in
    sda | sdb) printf 'ATA     \n' ;;
  esac
elif [[ $opts == *-dno\ MODEL* ]]; then
  case "$name" in
    sda) printf 'Samsung SSD 870 EVO 1TB\n' ;;
    # Some controllers repeat the vendor at the head of the model string.
    sdb) printf 'ATA WDC WD10EZEX-08WN4A0\n' ;;
  esac
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
    sdb)
      printf 'disk sdb  \n'
      printf 'part sdb1 ext4 /home\n'
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
[[ $out == "/dev/sda (931.5G)"* ]] ||
  fail "drive info does not double-prefix the device path" "$out"
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
[[ $out == "/dev/root (929.5G)"* ]] ||
  fail "drive info does not double-prefix the device path of a mapping" "$out"
pass "drive info walks up through a nested mapping"

# sdb reports the vendor twice: once as VENDOR and again at the head of MODEL.
# sda cannot cover this -- its model shares no word with its vendor, so it reads
# the same whether the labels are deduplicated or simply concatenated.
out=$(drive_info /dev/sdb)
[[ $out == *"ATA WDC WD10EZEX-08WN4A0"* ]] ||
  fail "drive info keeps a model that begins with the vendor" "$out"
[[ $out != *"ATA ATA"* ]] || fail "drive info does not duplicate the vendor" "$out"
pass "drive info does not duplicate a vendor already in the model"

# The dedup still has to resolve up first: a partition reports no vendor at all.
out=$(drive_info /dev/sdb1)
[[ $out == *"ATA WDC WD10EZEX-08WN4A0"* ]] ||
  fail "drive info labels a partition from its disk" "$out"
[[ $out != *"ATA ATA"* ]] || fail "drive info does not duplicate the vendor of a partition" "$out"
pass "drive info deduplicates the vendor after resolving to the disk"
