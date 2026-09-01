#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1788279117.sh"
packaged_hooks="$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
hooks_conf="$test_tmp/omarchy_hooks.conf"
cmdline="$test_tmp/cmdline"
crypttab="$test_tmp/crypttab.initramfs"
pci_devices="$test_tmp/pci-devices"
marker="$test_tmp/rebuild-complete"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin" "$pci_devices"
cp "$packaged_hooks" "$hooks_conf"
printf '%s\n' 'root=UUID=test rw' >"$cmdline"
: >"$calls"

cat >"$stub_bin/findmnt" <<'SH'
#!/bin/bash

case "$*" in
  "-nro SOURCE --nofsroot /") printf '%s\n' /dev/test-root ;;
  "-nro FSTYPE /") printf '%s\n' "${ROOT_FSTYPE:-ext4}" ;;
  *) exit 1 ;;
esac
SH

cat >"$stub_bin/lsblk" <<'SH'
#!/bin/bash

(( $# == 3 )) || exit 64
[[ $1 == "-nrso" && $2 == "TYPE" && $3 == "/dev/test-root" ]] || exit 64
printf '%b' "${ROOT_STACK:-part\ndisk\n}"
SH

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash

[[ $1 == "limine-mkinitcpio" ]] && (( ${LIMINE_MKINITCPIO_INSTALLED:-1} == 1 ))
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
(( ${REBUILD_FAIL:-0} == 0 ))
SH

cat >"$stub_bin/mkinitcpio" <<'SH'
#!/bin/bash

printf 'mkinitcpio' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
(( ${REBUILD_FAIL:-0} == 0 ))
SH

chmod +x "$stub_bin"/*

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_MKINITCPIO_HOOKS_CONF="$hooks_conf" \
    OMARCHY_PLAIN_ROOT_REBUILD_MARKER="$marker" \
    OMARCHY_ROOT_CMDLINE_PATH="$cmdline" \
    OMARCHY_CRYPTTAB_INITRAMFS="$crypttab" \
    OMARCHY_PCI_DEVICES_PATH="$pci_devices" \
    bash -euo pipefail "$migration" >/dev/null
}

run_migration
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "a verified plain-root Limine install rebuilds its boot image"
first_sudo=$(grep '^sudo' "$calls" | head -1)
[[ $first_sudo == $'sudo\tlimine-mkinitcpio' ]] ||
  fail "hook classification stays unprivileged" "first sudo call: $first_sudo"
[[ -f $marker ]] || fail "a successful Limine rebuild records machine-wide completion"
pass "migration classifies without privilege and rebuilds a verified plain-root Limine install"

: >"$calls"
run_migration
[[ ! -s $calls ]] || fail "another user's migration run does not repeat the rebuild" "$(cat "$calls")"
pass "migration is machine-idempotent across users"

rm -f "$marker"
: >"$calls"
LIMINE_MKINITCPIO_INSTALLED=0 run_migration
grep -Fxq $'mkinitcpio\t-P' "$calls" ||
  fail "a non-Limine install rebuilds all initramfs images" "$(cat "$calls")"
[[ -f $marker ]] || fail "a successful mkinitcpio rebuild records machine-wide completion"
pass "migration falls back to mkinitcpio"

rm -f "$marker"
: >"$calls"
if REBUILD_FAIL=1 run_migration; then
  fail "a failed rebuild fails the migration"
fi
[[ ! -e $marker ]] || fail "a failed rebuild remains retryable"

: >"$calls"
run_migration
grep -Fxq 'limine-mkinitcpio' "$calls" || fail "a failed rebuild is retried"
[[ -f $marker ]] || fail "the successful retry records machine-wide completion"
pass "migration retries a failed rebuild"

rm -f "$marker"
: >"$calls"
ROOT_STACK=$'crypt\npart\ndisk\n' run_migration
[[ ! -s $calls ]] || fail "an encrypted root is left alone" "$(cat "$calls")"
[[ ! -e $marker ]] || fail "an encrypted root is not marked as rebuilt"
pass "migration skips roots whose installed config retains encrypt"

rm -f "$marker"
: >"$calls"
echo 'HOOKS=(base udev block encrypt filesystems fsck)' >"$hooks_conf"
run_migration
[[ ! -s $calls ]] || fail "a user-edited hook config that retains encrypt is left alone" "$(cat "$calls")"
pass "migration skips user-edited hook configuration"

rm -f "$hooks_conf"
: >"$calls"
run_migration
[[ ! -s $calls ]] || fail "a missing installed hook config is left alone" "$(cat "$calls")"
pass "migration skips installs without the hook configuration"
