#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

defaults_conf="$ROOT/etc/limine-entry-tool.d/omarchy-defaults.conf"
migration="$ROOT/migrations/1788507775.sh"

grep -Fqx 'KERNEL_CMDLINE[default]+=" usbcore.autosuspend=-1"' "$defaults_conf" ||
  fail "USB autosuspend is disabled through the kernel command line"
[[ ! -e $ROOT/etc/modprobe.d/omarchy-usb-autosuspend.conf ]] ||
  fail "the ineffective usbcore modprobe option is removed"
pass "USB autosuspend policy is expressed as a working kernel parameter"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
legacy_conf="$test_tmp/omarchy-usb-autosuspend.conf"
running_cmdline="$test_tmp/cmdline"
rebuild_marker="$test_tmp/rebuild-complete"
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

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash
printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_USB_AUTOSUSPEND_DEFAULTS_CONF="$defaults_conf" \
    OMARCHY_USB_AUTOSUSPEND_LEGACY_CONF="$legacy_conf" \
    OMARCHY_USB_AUTOSUSPEND_RUNNING_CMDLINE="$running_cmdline" \
    OMARCHY_USB_AUTOSUSPEND_REBUILD_MARKER="$rebuild_marker" \
    bash -euo pipefail "$migration" >/dev/null
}

echo 'options usbcore autosuspend=-1' >"$legacy_conf"
echo 'quiet splash' >"$running_cmdline"
run_migration

[[ ! -e $legacy_conf ]] || fail "migration removes the exact obsolete config"
grep -Fxq 'limine-mkinitcpio' "$calls" || fail "migration rebuilds the boot image"
grep -Fxq $'omarchy-state\tset\treboot-required' "$calls" || fail "migration requests a reboot"
[[ -f $rebuild_marker ]] || fail "migration records the machine-wide rebuild"
pass "migration replaces the obsolete setting and rebuilds once"

: >"$calls"
run_migration
[[ ! -s $calls ]] || fail "migration does not repeat a recorded rebuild" "$(cat "$calls")"
pass "migration is machine-idempotent before reboot"

printf '%s\n' '# administrator note' 'options usbcore autosuspend=-1' >"$legacy_conf"
echo 'quiet splash usbcore.autosuspend=-1' >"$running_cmdline"
rm -f "$rebuild_marker"
: >"$calls"
run_migration

[[ -e $legacy_conf ]] || fail "migration preserves an administrator-modified config"
[[ ! -s $calls ]] || fail "a booted kernel with the parameter needs no rebuild" "$(cat "$calls")"
pass "migration preserves custom files and skips an active parameter"
