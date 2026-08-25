#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787601557.sh"
packaged_defaults="$ROOT/etc/limine-entry-tool.d/omarchy-defaults.conf"
upgrade_to_quattro="$ROOT/bin/omarchy-upgrade-to-quattro"

grep -Fq 'KERNEL_CMDLINE[default]+=" usbcore.autosuspend=-1"' "$packaged_defaults" ||
  fail "the packaged Limine defaults disable USB autosuspend on the kernel cmdline"
pass "packaged Limine defaults set usbcore.autosuspend=-1"

[[ ! -e $ROOT/etc/modprobe.d/omarchy-usb-autosuspend.conf ]] ||
  fail "the useless usbcore modprobe drop-in is still shipped"
! grep -Fq '/etc/modprobe.d/omarchy-usb-autosuspend.conf' "$upgrade_to_quattro" ||
  fail "the quattro upgrade still overwrites the removed usbcore modprobe drop-in"
pass "modprobe drop-in is gone and not packaged as an upgrade overwrite"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash

(( ${LIMINE_MKINITCPIO_INSTALLED:-1} == 1 ))
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash

echo 'limine-mkinitcpio' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

defaults_conf="$test_tmp/omarchy-defaults.conf"
running_cmdline="$test_tmp/cmdline"
rebuild_marker="$test_tmp/rebuild-complete"
modprobe_conf="$test_tmp/omarchy-usb-autosuspend.conf"

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_LIMINE_DEFAULTS_CONF="$defaults_conf" \
    OMARCHY_RUNNING_CMDLINE="$running_cmdline" \
    OMARCHY_USB_AUTOSUSPEND_REBUILD_MARKER="$rebuild_marker" \
    OMARCHY_USB_AUTOSUSPEND_MODPROBE="$modprobe_conf" \
    bash -euo pipefail "$migration" >/dev/null
}

# Existing install: packaged defaults have not yet landed, leftover modprobe
# drop-in is still on disk, boot image still has the machine's root parameters
# and none of usbcore.autosuspend=-1.
cat >"$defaults_conf" <<'EOF'
TARGET_OS_NAME="Omarchy"

KERNEL_CMDLINE[default]+=" quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0"
KERNEL_CMDLINE[default]+=" initramfs_async=0"
EOF
echo 'options usbcore autosuspend=-1' >"$modprobe_conf"
echo 'quiet splash cryptdevice=PARTUUID=fake:root root=/dev/mapper/root rw' >"$running_cmdline"

run_migration

grep -Fq 'KERNEL_CMDLINE[default]+=" usbcore.autosuspend=-1"' "$defaults_conf" ||
  fail "migration appends usbcore.autosuspend=-1 to the Limine defaults"
grep -Fq 'initramfs_async=0' "$defaults_conf" ||
  fail "migration leaves existing Limine defaults in place"
[[ ! -e $modprobe_conf ]] || fail "migration removes the leftover modprobe drop-in"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "a boot image missing usbcore.autosuspend=-1 is rebuilt"
[[ -f $rebuild_marker ]] || fail "the rebuild records the machine-wide repair"
pass "migration adds usbcore.autosuspend=-1 when it is missing"

: >"$calls"
run_migration

(( $(grep -c 'usbcore.autosuspend=-1' "$defaults_conf") == 1 )) ||
  fail "migration does not append usbcore.autosuspend=-1 twice"
[[ ! -s $calls ]] || fail "a recorded rebuild is not repeated" "$(cat "$calls")"
pass "migration is a no-op when usbcore.autosuspend=-1 is already present"

rm -f "$rebuild_marker"
: >"$calls"
run_migration

grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "an interrupted rebuild is retried"
(( $(grep -c 'usbcore.autosuspend=-1' "$defaults_conf") == 1 )) ||
  fail "a rebuild retry does not duplicate the cmdline parameter"
pass "migration retries an interrupted rebuild without duplicating the parameter"

# Package already wrote the defaults (or a previous run did) and the boot
# image already carries the parameter, including the machine's root unlock.
cp "$packaged_defaults" "$defaults_conf"
configured=$(sed -n 's/^KERNEL_CMDLINE\[default\]+="\(.*\)"[[:space:]]*$/\1/p' "$defaults_conf" | tr '\n' ' ')
echo "cryptdevice=PARTUUID=fake:root root=/dev/mapper/root rw $configured" >"$running_cmdline"
rm -f "$rebuild_marker"
: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "a boot image that already has usbcore.autosuspend=-1 is left alone" "$(cat "$calls")"
[[ ! -e $rebuild_marker ]] || fail "an untouched machine is not marked as repaired"
(( $(grep -c 'usbcore.autosuspend=-1' "$defaults_conf") == 1 )) ||
  fail "a current boot image does not get a second cmdline line"
pass "migration is a no-op when the running cmdline already has the parameter"

echo 'quiet splash cryptdevice=PARTUUID=fake:root root=/dev/mapper/root rw' >"$running_cmdline"
: >"$calls"
LIMINE_MKINITCPIO_INSTALLED=0 run_migration

[[ ! -s $calls ]] || fail "installs without limine-mkinitcpio are skipped" "$(cat "$calls")"
grep -Fq 'cryptdevice=PARTUUID=fake:root' "$running_cmdline" ||
  fail "migration must not rewrite the running cmdline"

mv "$defaults_conf" "$defaults_conf.away"
run_migration
mv "$defaults_conf.away" "$defaults_conf"

[[ ! -s $calls ]] || fail "installs without the Limine defaults are skipped" "$(cat "$calls")"
pass "migration skips installs it does not apply to"
