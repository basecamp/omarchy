#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787076745.sh"

[[ -f $migration ]] || fail "T2 ESP migration exists"
! grep -q '^#!' "$migration" || fail "T2 ESP migration has no shebang"
grep -Fq 'echo "Point T2 overlay Limine at /boot/efi and write a linux-t2 entry"' "$migration" ||
  fail "T2 ESP migration starts with an echo"
grep -Fq 'lspci -nn | grep "106b:180[12]" >/dev/null' "$migration" ||
  fail "T2 ESP migration uses the same PCI check as fix-t2.sh"
! grep -E 'lspci[^[:space:]]*[[:space:]].*grep -q' "$migration" >/dev/null ||
  fail "T2 ESP migration does not grep -q a chatty lspci"
pass "T2 ESP migration is a T2-gated quattro migration"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the T2
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no T2 hardware" (#6608).
if (( ${T2_HARDWARE:-0} == 1 )); then
  echo '01:00.0 Bridge [0680]: Apple Inc. T2 Security Chip [106b:1801]'
fi
for _ in {1..4096}; do
  echo '02:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

chmod +x "$stub_bin"/*

boot="$test_tmp/boot"
esp="$test_tmp/boot/efi"
limine_default="$test_tmp/etc/default/limine"
reset_enroll="$test_tmp/hooks/10-limine-reset-enroll"
cmdline_file="$test_tmp/cmdline"

mkdir -p "$boot" "$esp/EFI/BOOT" "$esp/EFI/limine" "$(dirname "$limine_default")" "$(dirname "$reset_enroll")"

cp "$ROOT/default/limine/default.conf" "$limine_default"
cp "$ROOT/default/limine/limine.conf" "$esp/limine.conf"
cp "$ROOT/default/limine/limine.conf" "$esp/EFI/BOOT/limine.conf"
cp "$ROOT/default/limine/limine.conf" "$esp/EFI/limine/limine.conf"
printf 'vmlinuz-linux-t2\n' >"$boot/vmlinuz-linux-t2"
printf 'initramfs-linux-t2\n' >"$boot/initramfs-linux-t2.img"
printf 'limine-reset-enroll\n' >"$reset_enroll"
printf 'root=/dev/mapper/root rw rootflags=subvol=@ intel_iommu=on iommu=pt\n' >"$cmdline_file"

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_T2_BOOT="$boot" \
    OMARCHY_T2_ESP="$esp" \
    OMARCHY_T2_BOOT_FSTYPE="$boot_fstype" \
    OMARCHY_T2_ESP_FSTYPE="$esp_fstype" \
    OMARCHY_T2_LIMINE_DEFAULT="$limine_default" \
    OMARCHY_T2_RESET_ENROLL="$reset_enroll" \
    OMARCHY_T2_RUNNING_CMDLINE="$cmdline_file" \
    bash -euo pipefail "$migration" >/dev/null
}

assert_linux_t2_entry() {
  local conf=$1
  local label=$2

  grep -qx '/Omarchy' "$conf" || fail "$label writes /Omarchy"
  grep -qx '//linux-t2' "$conf" || fail "$label writes //linux-t2"
  grep -Fq 'protocol: linux' "$conf" || fail "$label writes a protocol: linux stanza"
  grep -Fq 'path: boot():/vmlinuz-linux-t2' "$conf" || fail "$label points at vmlinuz-linux-t2 on the ESP"
  grep -Fq 'module_path: boot():/initramfs-linux-t2.img' "$conf" ||
    fail "$label points at initramfs-linux-t2.img on the ESP"
  grep -Fq 'cmdline: root=/dev/mapper/root rw rootflags=subvol=@ intel_iommu=on iommu=pt' "$conf" ||
    fail "$label uses the running kernel command line"
  grep -Fq 'interface_branding: Omarchy Bootloader' "$conf" ||
    fail "$label keeps the Omarchy branding template"
}

boot_fstype=btrfs
esp_fstype=vfat
T2_HARDWARE=1 run_migration

grep -Eq '^ESP_PATH=["'\'']?/boot/efi["'\'']?$' "$limine_default" ||
  fail "overlay T2 migration sets ESP_PATH=/boot/efi"
! grep -Eq '^ESP_PATH=["'\'']?/boot["'\'']?$' "$limine_default" ||
  fail "overlay T2 migration replaces ESP_PATH=/boot"
assert_linux_t2_entry "$esp/limine.conf" "ESP limine.conf"
assert_linux_t2_entry "$esp/EFI/BOOT/limine.conf" "EFI fallback limine.conf"
assert_linux_t2_entry "$esp/EFI/limine/limine.conf" "EFI/limine limine.conf"
cmp -s "$boot/vmlinuz-linux-t2" "$esp/vmlinuz-linux-t2" ||
  fail "overlay T2 migration copies vmlinuz-linux-t2 onto the ESP"
cmp -s "$boot/initramfs-linux-t2.img" "$esp/initramfs-linux-t2.img" ||
  fail "overlay T2 migration copies initramfs-linux-t2.img onto the ESP"
[[ -e ${reset_enroll}.disabled ]] || fail "overlay T2 migration disables the Limine enroll reset hook"
[[ ! -e $reset_enroll ]] || fail "the enroll reset hook is renamed, not left in place"
pass "T2 overlay ESP at /boot/efi gets /Omarchy, //linux-t2, and ESP_PATH"

: >"$calls"
T2_HARDWARE=1 run_migration

[[ ! -s $calls ]] || fail "an already repaired T2 overlay is left unchanged" "$(cat "$calls")"
(( $(grep -c '^/Omarchy$' "$esp/limine.conf") == 1 )) ||
  fail "a second run does not duplicate /Omarchy"
(( $(grep -c '^//linux-t2$' "$esp/limine.conf") == 1 )) ||
  fail "a second run does not duplicate //linux-t2"
pass "T2 overlay ESP migration is idempotent"

cp "$ROOT/default/limine/default.conf" "$limine_default"
cp "$ROOT/default/limine/limine.conf" "$boot/limine.conf"
printf 'limine-reset-enroll\n' >"$reset_enroll"
rm -f "${reset_enroll}.disabled"
: >"$calls"

boot_fstype=vfat
esp_fstype=vfat
T2_HARDWARE=1 run_migration

grep -Eq '^ESP_PATH=["'\'']?/boot["'\'']?$' "$limine_default" ||
  fail "official /boot-as-ESP keeps ESP_PATH=/boot"
! grep -q '^/Omarchy$' "$boot/limine.conf" ||
  fail "official /boot-as-ESP does not write /Omarchy"
! grep -q '^//linux-t2$' "$boot/limine.conf" ||
  fail "official /boot-as-ESP does not write //linux-t2"
[[ -e $reset_enroll ]] || fail "official /boot-as-ESP leaves the enroll reset hook enabled"
[[ ! -e ${reset_enroll}.disabled ]] || fail "official /boot-as-ESP does not disable the enroll reset hook"
[[ ! -s $calls ]] || fail "official /boot-as-ESP is a no-op" "$(cat "$calls")"
pass "official /boot-as-ESP path is a no-op"

cp "$ROOT/default/limine/default.conf" "$limine_default"
cp "$ROOT/default/limine/limine.conf" "$esp/limine.conf"
printf 'limine-reset-enroll\n' >"$reset_enroll"
rm -f "${reset_enroll}.disabled" "$esp/vmlinuz-linux-t2" "$esp/initramfs-linux-t2.img"
: >"$calls"

boot_fstype=btrfs
esp_fstype=vfat
T2_HARDWARE=0 run_migration

grep -Eq '^ESP_PATH=["'\'']?/boot["'\'']?$' "$limine_default" ||
  fail "non-T2 Limine configuration is unchanged"
! grep -q '^//linux-t2$' "$esp/limine.conf" || fail "non-T2 ESP limine.conf is unchanged"
[[ -e $reset_enroll ]] || fail "non-T2 enroll reset hook is unchanged"
[[ ! -s $calls ]] || fail "non-T2 systems skip the ESP repair" "$(cat "$calls")"
pass "T2 ESP migration skips unrelated hardware"
