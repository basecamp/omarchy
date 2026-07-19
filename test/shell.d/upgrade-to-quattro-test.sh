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
