#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1788059374.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_root="$test_tmp/root"
stub_bin="$test_tmp/bin"
transformed="$test_tmp/migration.sh"
mkdir -p "$stub_bin"

sed \
  -e "s#/usr/share#$fake_root/usr/share#g" \
  -e "s#/etc#$fake_root/etc#g" \
  "$migration" >"$transformed"

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == "-Qo" ]] || exit 98
if [[ ${PACMAN_ERROR_PATH:-} == "$2" ]]; then
  echo "error: package database unavailable" >&2
  exit 2
elif [[ ${OWNED_PATH:-} == "$2" ]]; then
  echo "$2 is owned by another-package 1-1"
  exit 0
else
  echo "error: No package owns $2" >&2
  exit 1
fi
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$stub_bin"/*

legacy_login="$fake_root/etc/sddm.conf.d/99-omarchy-login.conf"
legacy_hyprland="$fake_root/usr/share/sddm/hyprland.conf"
legacy_usb="$fake_root/etc/modprobe.d/disable-usb-autosuspend.conf"
legacy_passwd="$fake_root/etc/sudoers.d/passwd-tries"
legacy_asdcontrol="$fake_root/etc/sudoers.d/asdcontrol"
legacy_faster="$fake_root/etc/systemd/system/user@.service.d/faster-shutdown.conf"
legacy_system_nofile="$fake_root/etc/systemd/system.conf.d/99-omarchy-nofile.conf"
legacy_user_nofile="$fake_root/etc/systemd/user.conf.d/99-omarchy-nofile.conf"
legacy_sysctl="$fake_root/etc/sysctl.d/99-sysctl.conf"
logind="$fake_root/etc/systemd/logind.conf"

reset_root() {
  rm -rf "$fake_root"
  mkdir -p \
    "$(dirname "$legacy_login")" \
    "$(dirname "$legacy_hyprland")" \
    "$(dirname "$legacy_usb")" \
    "$(dirname "$legacy_passwd")" \
    "$(dirname "$legacy_faster")" \
    "$(dirname "$legacy_system_nofile")" \
    "$(dirname "$legacy_user_nofile")" \
    "$(dirname "$legacy_sysctl")" \
    "$(dirname "$logind")"
}

write_line_terminated() {
  local path=$1
  local content=$2

  printf '%s\n' "$content" >"$path"
}

run_migration() {
  PATH="$stub_bin:$PATH" \
    OWNED_PATH="${OWNED_PATH:-}" \
    PACMAN_ERROR_PATH="${PACMAN_ERROR_PATH:-}" \
    bash -euo pipefail "$transformed" >"$test_tmp/out" 2>"$test_tmp/err"
}

reset_root
write_line_terminated "$legacy_login" $'[Theme]\nCurrent=omarchy\n\n[Users]\nRememberLastUser=true\nRememberLastSession=true'
write_line_terminated "$legacy_hyprland" $'# Minimal Hyprland config for the SDDM Wayland greeter.\n# SDDM starts the greeter itself after the compositor is ready.\nmisc {\n  disable_hyprland_logo = true\n  disable_splash_rendering = true\n  force_default_wallpaper = 0\n}\n\nanimations {\n  enabled = false\n}'
write_line_terminated "$legacy_usb" 'options usbcore autosuspend=-1'
write_line_terminated "$legacy_passwd" 'Defaults passwd_tries=10'
write_line_terminated "$legacy_asdcontrol" "$(id -un) ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol"
write_line_terminated "$legacy_faster" $'[Service]\nTimeoutStopSec=5s'
write_line_terminated "$legacy_system_nofile" $'[Manager]\nDefaultLimitNOFILESoft=65536'
write_line_terminated "$legacy_user_nofile" $'[Manager]\nDefaultLimitNOFILE=65536:524288'
write_line_terminated "$legacy_sysctl" $'keep=this\nnet.ipv4.tcp_mtu_probing=1\nnet.ipv4.tcp_mtu_probing=1\nand=this'
write_line_terminated "$logind" 'HandlePowerKey=ignore'

run_migration

for retired in \
  "$legacy_login" \
  "$legacy_hyprland" \
  "$legacy_usb" \
  "$legacy_passwd" \
  "$legacy_asdcontrol" \
  "$legacy_faster" \
  "$legacy_system_nofile" \
  "$legacy_user_nofile"; do
  [[ ! -e $retired ]] || fail "the ownership migration leaves known legacy state at $retired"
done
grep -qx 'keep=this' "$legacy_sysctl" || fail "the sysctl cleanup removes unrelated local state"
grep -qx 'and=this' "$legacy_sysctl" || fail "the sysctl cleanup removes unrelated trailing state"
if grep -q '^net\.ipv4\.tcp_mtu_probing=1$' "$legacy_sysctl"; then
  fail "the sysctl cleanup leaves the superseded Omarchy setting"
fi
grep -qx 'HandlePowerKey=ignore' "$logind" || fail "the ownership migration rewrites a package-owned administrator setting"
pass "known Omarchy 3 and early Quattro artifacts retire byte-for-byte"

run_migration || fail "the legacy state migration is not idempotent"
pass "the legacy state transition is idempotent"

reset_root
write_line_terminated "$legacy_login" $'[Users]\nRememberLastUser=true\nRememberLastSession=true'
write_line_terminated "$legacy_asdcontrol" "$(id -un) ALL=(ALL) NOPASSWD: /usr/local/bin/asdcontrol"
run_migration
[[ ! -e $legacy_login ]] || fail "the migration misses the later users-only SDDM variant"
[[ ! -e $legacy_asdcontrol ]] || fail "the migration misses the historical /usr/local asdcontrol rule"
pass "all released legacy content variants are recognized"

reset_root
write_line_terminated "$legacy_login" 'administrator changed this'
write_line_terminated "$legacy_usb" $'options usbcore autosuspend=-1\n'
write_line_terminated "$legacy_asdcontrol" 'another-user ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol'
write_line_terminated "$legacy_faster" $'[Service]\nTimeoutStopSec=5s'
write_line_terminated "$test_tmp/symlink-target" 'Defaults passwd_tries=10'
ln -s "$test_tmp/symlink-target" "$legacy_passwd"
OWNED_PATH="$legacy_faster" run_migration

grep -qx 'administrator changed this' "$legacy_login" || fail "the migration removes a locally changed SDDM file"
[[ -f $legacy_usb ]] || fail "the migration accepts extra trailing bytes as an exact legacy file"
grep -qx 'another-user ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol' "$legacy_asdcontrol" ||
  fail "the migration revokes another account's sudoers rule"
[[ -L $legacy_passwd ]] || fail "the migration follows a symlink at a legacy path"
[[ -f $legacy_faster ]] || fail "the migration removes another package's file"
pass "local, linked, foreign-user, and package-owned state is preserved"

reset_root
write_line_terminated "$legacy_usb" 'options usbcore autosuspend=-1'
if PACMAN_ERROR_PATH="$legacy_usb" run_migration; then
  fail "a package database error is treated as authorization to delete"
fi
[[ -f $legacy_usb ]] || fail "a package database error removes the legacy path"
grep -q 'Unable to verify package ownership' "$test_tmp/err" || fail "the package database error is hidden"
pass "ownership cleanup fails closed when Pacman cannot answer"
