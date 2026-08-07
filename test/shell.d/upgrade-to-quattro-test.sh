#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

upgrade_to_quattro="$ROOT/bin/omarchy-upgrade-to-quattro"

snapshot_line=$(grep -n '^create_pre_upgrade_snapshot$' "$upgrade_to_quattro" | cut -d: -f1)
pacman_line=$(grep -n '^configure_pacman_channel$' "$upgrade_to_quattro" | cut -d: -f1)
[[ -n $snapshot_line && -n $pacman_line ]] || fail "upgrade snapshot and first mutation calls exist"
(( snapshot_line < pacman_line )) || fail "upgrade snapshot runs before pacman configuration"
grep -F 'omarchy-snapshot create || (($? == 127))' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade snapshots the system before mutation"

grep -F 'pacman -Syu --needed' "$upgrade_to_quattro" >/dev/null
grep -F 'omarchy-update-aur-pkgs' "$upgrade_to_quattro" >/dev/null
grep -F 'omarchy-update-available' "$upgrade_to_quattro" >/dev/null
grep -F 'omarchy-update-mise' "$upgrade_to_quattro" >/dev/null
grep -F 'run_final_system_package_upgrade' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade completes package update checks"

grep -F 'run_post_upgrade_migrations' "$upgrade_to_quattro" >/dev/null
grep -F 'omarchy-migrate' "$upgrade_to_quattro" >/dev/null
grep -F 'dust' "$upgrade_to_quattro" >/dev/null
grep -F 'satty' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade applies packaged migrations"

if grep -F 'skip-first-run-update-notification' "$upgrade_to_quattro" >/dev/null; then
  fail "Omarchy 4 upgrade does not use notification-specific first-run state"
fi
pass "Omarchy 4 upgrade completes first-run as one lifecycle"

grep -F '"$root/bin/omarchy-done" mark first-run-user' "$upgrade_to_quattro" >/dev/null
grep -F 'rm -f "$state_dir/first-run-user.done"' "$upgrade_to_quattro" >/dev/null
grep -F '"$root/bin/omarchy-done" mark finalize-user' "$upgrade_to_quattro" >/dev/null
grep -F 'rm -f "$state_dir/finalize-user.done"' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade completes first-run and migrates legacy completion markers"

grep -F 'configure_snapper_policy' "$upgrade_to_quattro" >/dev/null
grep -F '/usr/share/omarchy/install/config/snapper.sh' "$upgrade_to_quattro" >/dev/null
grep -F 'bash -euo pipefail "$snapper_config_script"' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade normalizes Snapper retention"

grep -F 'configure_lock_authentication' "$upgrade_to_quattro" >/dev/null
grep -F 'OMARCHY_INSTALL_USER="$target_user"' "$upgrade_to_quattro" >/dev/null
grep -F '"$setup_lock"' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade configures lock screen authentication for the target user"

grep -F 'OMARCHY_UPGRADE_TO_QUATTRO_LIVE=1' "$upgrade_to_quattro" >/dev/null
grep -F 'systemd-networkd.service' "$upgrade_to_quattro" >/dev/null
grep -F 'systemd-networkd.socket' "$upgrade_to_quattro" >/dev/null
grep -F 'systemd-networkd-resolve-hook.socket' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade retires systemd-networkd for NetworkManager"

grep -F 'omarchy-bar defaults' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade restores service-aware bar defaults"

grep -F 'install_hardware_transition_packages' "$upgrade_to_quattro" >/dev/null
grep -F 'sof-firmware' "$upgrade_to_quattro" >/dev/null
grep -F 'vulkan-intel' "$upgrade_to_quattro" >/dev/null
grep -F 'apply_user_hardware_transition' "$upgrade_to_quattro" >/dev/null
grep -F 'DX13260' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade backfills hardware support from the legacy release"

grep -F 'omarchy-refresh-applications' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade refreshes application launchers"

grep -F '/etc/systemd/system.conf.d/99-omarchy-nofile.conf' "$upgrade_to_quattro" >/dev/null
grep -F '/etc/systemd/user.conf.d/99-omarchy-nofile.conf' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade removes stale nofile drop-ins"

cmdline_line=$(grep -n '^preserve_kernel_cmdline_root$' "$upgrade_to_quattro" | cut -d: -f1)
packages_line=$(grep -n '^install_omarchy_quattro_packages$' "$upgrade_to_quattro" | cut -d: -f1)
[[ -n $cmdline_line && -n $packages_line ]] || fail "kernel cmdline preservation and package install calls exist"
(( packages_line < cmdline_line )) || fail "kernel cmdline preservation runs once limine-mkinitcpio is installed"
grep -F '/etc/default/limine' "$upgrade_to_quattro" >/dev/null
grep -F 'KERNEL_CMDLINE[default]+=" ${boot_params[*]}"' "$upgrade_to_quattro" >/dev/null
grep -F 'cat /proc/cmdline' "$upgrade_to_quattro" >/dev/null
grep -F 'findmnt -no UUID /' "$upgrade_to_quattro" >/dev/null
grep -F 'rootflags=subvol=' "$upgrade_to_quattro" >/dev/null
grep -F 'cryptdevice' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade preserves the kernel cmdline root parameters"

# Kernel parameters can quote spaces (dm-mod.create="0 972 linear ...");
# word splitting would truncate them and glob-expand the rest.
param_re='^[[:space:]]*(([^[:space:]"]|"[^"]*")+)'
grep -F "param_re='^[[:space:]]*(([^[:space:]\"]|\"[^\"]*\")+)'" "$upgrade_to_quattro" >/dev/null

# limine-entry-tool.conf ships "#KERNEL_CMDLINE[default]+=rw root=UUID=..." as a
# commented example, so the guard matches assignment lines and not the bare
# string, and only the default key feeds the entries the fix repairs.
cmdline_guard='^[[:space:]]*KERNEL_CMDLINE\[default\][+]?='
grep -F "pin_line='^[[:space:]]*KERNEL_CMDLINE" "$upgrade_to_quattro" >/dev/null
if printf '%s\n' '#KERNEL_CMDLINE[default]+=rw root=UUID=...' | grep -qE "$cmdline_guard"; then
  fail "kernel cmdline guard ignores the commented example in limine-entry-tool.conf"
fi
if printf '%s\n' 'KERNEL_CMDLINE[fallback]+=" root=UUID=x"' | grep -qE "$cmdline_guard"; then
  fail "kernel cmdline guard does not let a fallback-only pin cover the default entries"
fi
if ! printf '%s\n' 'KERNEL_CMDLINE[default]+=" root=UUID=x rw"' | grep -qE "$cmdline_guard"; then
  fail "kernel cmdline guard still matches a real assignment"
fi
# Mirrors the guard's value walk: root= must appear as its own parameter, so
# systemd.volatile-root= and a quoted decoy cannot count as a pin.
grep -F '[[ ${BASH_REMATCH[1]} == root=* ]] && return 0' "$upgrade_to_quattro" >/dev/null
pin_value_has_root() {
  local value=${1#*=}
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  value=${value#[\"\']}
  value=${value%[\"\']}
  while [[ $value =~ $param_re ]]; do
    [[ ${BASH_REMATCH[1]} == root=* ]] && return 0
    value=${value:${#BASH_REMATCH[0]}}
  done
  return 1
}
pin_value_has_root 'KERNEL_CMDLINE[default]+=" root=UUID=x rw"' ||
  fail "kernel cmdline guard still accepts a quoted root= pin"
pin_value_has_root 'KERNEL_CMDLINE[default]+=root=UUID=x' ||
  fail "kernel cmdline guard still accepts an unquoted root= pin"
# The tool accepts whitespace between the operator and an opening quote.
pin_value_has_root 'KERNEL_CMDLINE[default]= "root=UUID=x rw"' ||
  fail "kernel cmdline guard still accepts a pin with whitespace before the quote"
if pin_value_has_root 'KERNEL_CMDLINE[default]+=" systemd.volatile-root=1"'; then
  fail "kernel cmdline guard does not mistake volatile-root= for a root= pin"
fi
if pin_value_has_root 'KERNEL_CMDLINE[default]+=systemd.setenv="root=decoy"'; then
  fail "kernel cmdline guard does not mistake a quoted decoy for a root= pin"
fi
# Once the omarchy drop-in appends with +=, limine-entry-tool ignores
# /etc/kernel/cmdline, so root= there never reaches the boot entries and must
# not skip the fix.
if grep -F 'as_root test -e /etc/kernel/cmdline' "$upgrade_to_quattro" >/dev/null; then
  fail "kernel cmdline guard does not treat the ignored /etc/kernel/cmdline as authoritative"
fi
pass "Omarchy 4 upgrade only treats real root= assignments as authoritative"

# /etc/default/limine is absent on exactly the machines this targets, and a
# missing operand makes grep exit 2, which the caller cannot tell apart from "no
# match". The guard filters the paths first so the exit status stays meaningful.
grep -F 'config_paths+=("$path")' "$upgrade_to_quattro" >/dev/null
grep -F 'if ((${#config_paths[@]})); then' "$upgrade_to_quattro" >/dev/null
# Only *.conf drop-ins count: the tool loads nothing else, so .pacnew or
# .pacsave litter pinning root= must not disarm the fix.
grep -F '/etc/limine-entry-tool.d/*.conf' "$upgrade_to_quattro" >/dev/null
guard_fixtures=$(mktemp -d)
trap 'rm -rf "$guard_fixtures"' EXIT
mkdir -p "$guard_fixtures/dropins"
printf '%s\n' 'KERNEL_CMDLINE[default]+=" root=UUID=real rw"' >"$guard_fixtures/dropins/99-pins.conf"
printf '%s\n' 'KERNEL_CMDLINE[default]+=" root=UUID=stale rw"' >"$guard_fixtures/dropins/99-stale.conf.pacsave"
guard_paths=()
for guard_path in "$guard_fixtures/absent" "$guard_fixtures/dropins"/*.conf; do
  if [[ -e $guard_path ]]; then
    guard_paths+=("$guard_path")
  fi
done
if ! ((${#guard_paths[@]})) || ! grep -qE "$cmdline_guard" "${guard_paths[@]}"; then
  fail "kernel cmdline guard still detects a drop-in pinning root= when another path is absent"
fi
[[ ${guard_paths[*]} == *"99-pins.conf"* && ${guard_paths[*]} != *"pacsave"* ]] ||
  fail "kernel cmdline guard only reads *.conf drop-ins"
pass "Omarchy 4 upgrade cmdline guard survives a missing config path"

token_cmdline='root=UUID=x dm-mod.create="0 972 linear /dev/sda 0" rw'
token_params=()
while [[ $token_cmdline =~ $param_re ]]; do
  token_params+=("${BASH_REMATCH[1]}")
  token_cmdline=${token_cmdline:${#BASH_REMATCH[0]}}
done
(( ${#token_params[@]} == 3 )) || fail "kernel cmdline tokenizer splits three parameters"
[[ ${token_params[1]} == 'dm-mod.create="0 972 linear /dev/sda 0"' ]] ||
  fail "kernel cmdline tokenizer keeps quoted parameters intact"
pass "Omarchy 4 upgrade copies quoted kernel parameters verbatim"

grep -F 'boot_params=("root=UUID=$root_uuid" "${boot_params[@]}")' "$upgrade_to_quattro" >/dev/null
grep -F '((have_mount_mode)) || boot_params+=(rw)' "$upgrade_to_quattro" >/dev/null
grep -F 'have_unlock' "$upgrade_to_quattro" >/dev/null
# Gated on a crypt layer in the stack, not on the /dev/mapper/* prefix, so plain
# LVM, dm-raid and multipath roots keep the repair path.
if grep -F '[[ $root_source == /dev/mapper/* ]] && ((!have_unlock))' "$upgrade_to_quattro" >/dev/null; then
  fail "kernel cmdline repair path does not treat every /dev/mapper root as encrypted"
fi
# lsblk reports only the target's own type, which is lvm on the standard
# container -> LVM PV -> root LV layout, so the crypt layer has to be looked for
# across the parents with -s or full-disk encryption slips through.
grep -F 'lsblk -nso TYPE "$root_source"' "$upgrade_to_quattro" >/dev/null
grep -F 'grep -qx crypt' "$upgrade_to_quattro" >/dev/null
grep -F '((root_stacks_crypt)) && ((!have_unlock))' "$upgrade_to_quattro" >/dev/null
# Without --nofsroot findmnt appends the subvolume, so an encrypted btrfs root
# reads /dev/mapper/cryptroot[/@] and lsblk cannot resolve it at all.
grep -F 'findmnt -no SOURCE --nofsroot /' "$upgrade_to_quattro" >/dev/null
# Read outside the branch that assigns it, and set -u treats a declared-but-
# unassigned local as unbound.
grep -F 'local root_stacks_crypt=0' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade repair path keeps captured parameters and refuses a partial dm-crypt cmdline"

grep -F -- '--only-section=.cmdline' "$upgrade_to_quattro" >/dev/null
grep -F 'as_root objcopy' "$upgrade_to_quattro" >/dev/null
# Token-anchored, so netroot= or systemd.volatile-root= cannot satisfy the
# verification.
grep -F "grep -qE '(^|[[:space:]])root='" "$upgrade_to_quattro" >/dev/null
# Read as root like every other /boot access, and scoped to the images
# limine-entry-tool generates, so a shared ESP cannot trigger a false warning.
grep -F "as_root find /boot/EFI/Linux -maxdepth 1 -name 'omarchy_linux*.efi'" "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade verifies the cmdline embedded in the UKIs"

grep -F 'rd.lvm.lv | rd.lvm.vg' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade carries the device assembly parameters over"

# A warning alone does not stop --reboot or a blind prompt confirmation; an
# unverified cmdline has to block the reboot itself.
grep -F 'boot_cmdline_unsafe=1' "$upgrade_to_quattro" >/dev/null
grep -F 'if (( boot_cmdline_unsafe )); then' "$upgrade_to_quattro" >/dev/null
unsafe_line=$(grep -n 'if (( boot_cmdline_unsafe )); then' "$upgrade_to_quattro" | cut -d: -f1)
reboot_line=$(grep -n 'Rebooting because --reboot was passed' "$upgrade_to_quattro" | cut -d: -f1)
[[ -n $unsafe_line && -n $reboot_line ]] || fail "reboot gate and reboot branch exist"
(( unsafe_line < reboot_line )) || fail "an unverified kernel cmdline blocks the reboot"
pass "Omarchy 4 upgrade refuses to reboot with an unverified kernel cmdline"
