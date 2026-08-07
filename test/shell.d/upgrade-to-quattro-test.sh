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

# The += drop-ins make limine-entry-tool ignore /etc/kernel/cmdline and
# /proc/cmdline, so only the tool's own merge can say whether root= survives.
# Queried for the default key, so a kernel-specific pin cannot cover for the
# entries this repairs.
grep -F 'limine-entry-tool --get-cmdline default' "$upgrade_to_quattro" >/dev/null
grep -F "grep -qE '(^|[[:space:]])root='" "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade asks limine-entry-tool whether root= survives"

# The crypt layer hides in the parents on LVM-on-LUKS, and a partial cmdline
# for an encrypted root must not be written at all.
grep -F 'findmnt -no SOURCE --nofsroot /' "$upgrade_to_quattro" >/dev/null
grep -F 'lsblk -nso TYPE "$root_source"' "$upgrade_to_quattro" >/dev/null
grep -F 'grep -qx crypt' "$upgrade_to_quattro" >/dev/null
grep -F '((have_mount_mode)) || boot_params+=(rw)' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade repair path refuses a partial dm-crypt cmdline"

# The cmdline that boots is the one embedded in the UKIs, and an unverified
# root= must block the reboot rather than just warn.
grep -F -- '--only-section=.cmdline' "$upgrade_to_quattro" >/dev/null
grep -F "as_root find /boot/EFI/Linux -maxdepth 1 -name 'omarchy_linux*.efi'" "$upgrade_to_quattro" >/dev/null
grep -F 'boot_cmdline_unsafe=1' "$upgrade_to_quattro" >/dev/null
unsafe_line=$(grep -n 'if (( boot_cmdline_unsafe )); then' "$upgrade_to_quattro" | cut -d: -f1)
reboot_line=$(grep -n 'Rebooting because --reboot was passed' "$upgrade_to_quattro" | cut -d: -f1)
[[ -n $unsafe_line && -n $reboot_line ]] || fail "reboot gate and reboot branch exist"
(( unsafe_line < reboot_line )) || fail "an unverified kernel cmdline blocks the reboot"
pass "Omarchy 4 upgrade verifies the UKIs and refuses to reboot unverified"
