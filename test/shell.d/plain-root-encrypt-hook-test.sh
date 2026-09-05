#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hooks_conf="$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
cmdline="$test_tmp/cmdline"
crypttab="$test_tmp/crypttab.initramfs"
pci_devices="$test_tmp/pci-devices"
mkdir -p "$stub_bin" "$pci_devices"

cat >"$stub_bin/findmnt" <<'SH'
#!/bin/bash

(( ${FINDMNT_FAIL:-0} == 0 )) || exit 1

case "$*" in
  "-nro SOURCE --nofsroot /") printf '%s\n' "${ROOT_SOURCE-/dev/test-root}" ;;
  "-nro FSTYPE /") printf '%s\n' "${ROOT_FSTYPE:-ext4}" ;;
  *) exit 1 ;;
esac
SH

cat >"$stub_bin/lsblk" <<'SH'
#!/bin/bash

(( ${LSBLK_FAIL:-0} == 0 )) || exit 1
(( $# == 3 )) || exit 64
[[ $1 == "-nrso" && $2 == "TYPE" && $3 == "${ROOT_SOURCE-/dev/test-root}" ]] || exit 64
printf '%b' "${ROOT_STACK-part\ndisk\n}"
SH

chmod +x "$stub_bin"/*

resolved_hooks() {
  local fstype="$1" stack="$2" kernel_cmdline="$3" crypttab_contents="${4:-missing}"

  printf '%s\n' "$kernel_cmdline" >"$cmdline"
  rm -rf "$crypttab"
  if [[ $crypttab_contents == "directory" ]]; then
    mkdir "$crypttab"
  elif [[ $crypttab_contents == "dangling" ]]; then
    ln -s "$test_tmp/missing-crypttab-target" "$crypttab"
  elif [[ $crypttab_contents != "missing" ]]; then
    printf '%b' "$crypttab_contents" >"$crypttab"
  fi

  PATH="$stub_bin:$PATH" \
    ROOT_FSTYPE="$fstype" \
    ROOT_STACK="$stack" \
    OMARCHY_ROOT_CMDLINE_PATH="$cmdline" \
    OMARCHY_CRYPTTAB_INITRAMFS="$crypttab" \
    OMARCHY_PCI_DEVICES_PATH="$pci_devices" \
    bash -uc "
      FILES=()
      MODULES=()
      XKBLAYOUT=us
      source '$hooks_conf'
      echo \"\${HOOKS[*]}\"
    "
}

baseline=$(FINDMNT_FAIL=1 resolved_hooks ext4 $'part\ndisk\n' 'root=UUID=test rw')
[[ " $baseline " == *" encrypt "* ]] || fail "the fail-closed baseline contains encrypt" "$baseline"
without_encrypt=${baseline/ encrypt / }

assert_hooks() {
  local description="$1" expected="$2"
  shift 2

  local actual
  actual=$(resolved_hooks "$@")
  [[ $actual == "$expected" ]] ||
    fail "$description" "expected: $expected"$'\n'"actual:   $actual"
  pass "$description"
}

assert_hooks "a direct ext4 root drops only encrypt" "$without_encrypt" \
  ext4 $'part\ndisk\n' 'root=UUID=test rw'
assert_hooks "a direct Btrfs root drops only encrypt" "$without_encrypt" \
  btrfs $'part\ndisk\n' 'root=UUID=test rw' $'\n  # no initramfs mappings\n'

assert_hooks "dm-crypt ancestry keeps encrypt" "$baseline" \
  ext4 $'crypt\npart\ndisk\n' 'root=/dev/mapper/root rw'
assert_hooks "LVM ancestry keeps encrypt" "$baseline" \
  ext4 $'lvm\npart\ndisk\n' 'root=/dev/mapper/vg-root rw'
assert_hooks "RAID ancestry keeps encrypt" "$baseline" \
  ext4 $'raid1\npart\ndisk\n' 'root=/dev/md0 rw'

for selector in \
  'cryptdevice=UUID=test:root' \
  'cryptkey=rootfs:/root.key' \
  'crypto=sha256:aes:256:0:0'; do
  assert_hooks "$selector keeps encrypt" "$baseline" \
    ext4 $'part\ndisk\n' "root=UUID=test rw $selector"
done

assert_hooks "an active initramfs crypttab row keeps encrypt" "$baseline" \
  ext4 $'part\ndisk\n' 'root=UUID=test rw' $'root UUID=test none luks\n'

FINDMNT_FAIL=1 assert_hooks "failed root discovery keeps encrypt" "$baseline" \
  ext4 $'part\ndisk\n' 'root=UUID=test rw'

LSBLK_FAIL=1 assert_hooks "failed ancestry discovery keeps encrypt" "$baseline" \
  ext4 $'part\ndisk\n' 'root=UUID=test rw'

ROOT_SOURCE='' assert_hooks "an empty root source keeps encrypt" "$baseline" \
  ext4 $'part\ndisk\n' 'root=UUID=test rw'

assert_hooks "an unknown ancestry type keeps encrypt" "$baseline" \
  ext4 $'part\nunknown\ndisk\n' 'root=UUID=test rw'
assert_hooks "an empty ancestry result keeps encrypt" "$baseline" \
  ext4 '' 'root=UUID=test rw'
assert_hooks "an unsupported root filesystem keeps encrypt" "$baseline" \
  xfs $'part\ndisk\n' 'root=UUID=test rw'

assert_hooks "an unreadable initramfs crypttab path keeps encrypt" "$baseline" \
  ext4 $'part\ndisk\n' 'root=UUID=test rw' directory
assert_hooks "a dangling initramfs crypttab symlink keeps encrypt" "$baseline" \
  ext4 $'part\ndisk\n' 'root=UUID=test rw' dangling

rm -f "$crypttab"
rm -f "$cmdline"
actual=$(
  PATH="$stub_bin:$PATH" \
    ROOT_FSTYPE=ext4 \
    ROOT_STACK=$'part\ndisk\n' \
    OMARCHY_ROOT_CMDLINE_PATH="$cmdline" \
    OMARCHY_CRYPTTAB_INITRAMFS="$crypttab" \
    OMARCHY_PCI_DEVICES_PATH="$pci_devices" \
    bash -uc "FILES=(); MODULES=(); XKBLAYOUT=us; source '$hooks_conf'; echo \"\${HOOKS[*]}\""
)
[[ $actual == "$baseline" ]] || fail "an unreadable kernel command line keeps encrypt"
pass "an unreadable kernel command line keeps encrypt"
