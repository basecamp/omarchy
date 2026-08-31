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

# The mirrors are repointed immediately before the keyrings go in, so only a
# forced refresh replaces the legacy database and its stale checksums.
grep -F 'pacman -Syy --noconfirm archlinux-keyring omarchy-keyring' "$upgrade_to_quattro" >/dev/null
if grep -F 'pacman -Sy --noconfirm archlinux-keyring omarchy-keyring' "$upgrade_to_quattro" >/dev/null; then
  fail "Omarchy 4 upgrade forces a database refresh before installing keyrings"
fi
pass "Omarchy 4 upgrade forces a database refresh before installing keyrings"

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
final_upgrade_line=$(grep -n '^run_final_system_package_upgrade$' "$upgrade_to_quattro" | cut -d: -f1)
migrations_line=$(grep -n '^run_post_upgrade_migrations$' "$upgrade_to_quattro" | cut -d: -f1)
[[ -n $final_upgrade_line && -n $migrations_line ]] ||
  fail "final package upgrade and migration calls exist"
(( final_upgrade_line < migrations_line )) ||
  fail "Omarchy migrations run after the final package upgrade"
pass "Omarchy 4 upgrade applies packaged migrations"

if grep -F 'skip-first-run-update-notification' "$upgrade_to_quattro" >/dev/null; then
  fail "Omarchy 4 upgrade does not use notification-specific first-run state"
fi
pass "Omarchy 4 upgrade completes first-run as one lifecycle"

grep -F 'touch "$done_dir/first-run-user" "$done_dir/finalize-user"' "$upgrade_to_quattro" >/dev/null
grep -F 'rm -f "$state_dir/first-run-user.done" "$state_dir/finalize-user.done"' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade completes first-run and migrates legacy completion markers"

# The script runs from the branch against whatever packaged tree the channel
# serves, so a packaged command missing from an older build must never be able
# to abort the upgrade partway through.
if grep -F '"$root/bin/omarchy-done"' "$upgrade_to_quattro" >/dev/null; then
  fail "Omarchy 4 upgrade writes completion markers without the packaged omarchy-done"
fi
pass "Omarchy 4 upgrade writes completion markers without the packaged omarchy-done"

for guarded_step in omarchy-refresh-applications 'omarchy-bar defaults'; do
  grep -F "run_as_user_omarchy $guarded_step ||" "$upgrade_to_quattro" >/dev/null ||
    fail "Omarchy 4 upgrade survives a packaged tree without $guarded_step"
done
pass "Omarchy 4 upgrade survives a packaged tree missing top-level commands"

grep -F 'configure_snapper_policy' "$upgrade_to_quattro" >/dev/null
grep -F '/usr/share/omarchy/install/config/snapper.sh' "$upgrade_to_quattro" >/dev/null
grep -F 'bash -euo pipefail "$snapper_config_script"' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade normalizes Snapper retention"

grep -F 'configure_lock_authentication' "$upgrade_to_quattro" >/dev/null
grep -F 'OMARCHY_INSTALL_USER="$target_user"' "$upgrade_to_quattro" >/dev/null
grep -F '"$apply_lock"' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade configures lock screen authentication for the target user"

grep -F 'install/helpers/browser-policy.sh' "$upgrade_to_quattro" >/dev/null ||
  fail "Omarchy 4 upgrade uses the shared browser-policy helper"
grep -F 'as_root test -f "$browser_policy_helper"' "$upgrade_to_quattro" >/dev/null ||
  fail "Omarchy 4 upgrade survives a packaged tree without the browser-policy helper"
if grep -F 'browser_policy_setup_group' "$upgrade_to_quattro" >/dev/null; then
  fail "Omarchy 4 upgrade does not create a browser-policy group"
fi
grep -F 'browser_policy_setup_dir /etc/chromium/policies/managed' "$upgrade_to_quattro" >/dev/null ||
  fail "Omarchy 4 upgrade creates a root-owned Chromium policy directory"
grep -F 'BROWSER_POLICY_MANAGED_DIRS' "$upgrade_to_quattro" >/dev/null ||
  fail "Omarchy 4 upgrade hardens every Chromium-family policy directory"
grep -F 'run_as_user_omarchy omarchy-theme-set-browser' "$upgrade_to_quattro" >/dev/null ||
  fail "Omarchy 4 upgrade rewrites browser theme colour after a headless theme-set"
if grep -E 'install -d -m 0?[27]?777 /etc/.*/policies|chmod a\+rw|2775' "$upgrade_to_quattro" >/dev/null; then
  fail "Omarchy 4 upgrade does not create a world-writable Chromium policy directory"
fi
pass "Omarchy 4 upgrade locks the Chromium policy directory to root"

grep -F 'OMARCHY_UPGRADE_TO_QUATTRO_LIVE=1' "$upgrade_to_quattro" >/dev/null
grep -F 'systemd-networkd.service' "$upgrade_to_quattro" >/dev/null
grep -F 'systemd-networkd.socket' "$upgrade_to_quattro" >/dev/null
grep -F 'systemd-networkd-resolve-hook.socket' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade retires systemd-networkd for NetworkManager"

# Booting with both managers enabled leaves them fighting over the Wi-Fi
# adapter, so enabling NetworkManager and disabling iwd cannot be separated by
# any step that might abort in between.
function_body() {
  awk -v name="$1" '$0 == name "() {" { inside = 1; next } inside && $0 == "}" { exit } inside' "$upgrade_to_quattro"
}

migrations_body=$(function_body run_post_upgrade_migrations)
grep -F 'fail "Omarchy migrations did not complete.' <<<"$migrations_body" >/dev/null ||
  fail "Omarchy 4 upgrade fails when a migration cannot complete"
grep -F 'omarchy-migrate --pending' <<<"$migrations_body" >/dev/null ||
  fail "Omarchy 4 upgrade verifies that migrations actually completed"
grep -F 'fail "Omarchy migrations are still pending.' <<<"$migrations_body" >/dev/null ||
  fail "Omarchy 4 upgrade fails when a successful migration command leaves pending work"
grep -F 'pending_status != 1' <<<"$migrations_body" >/dev/null ||
  fail "Omarchy 4 upgrade distinguishes no pending work from a failed verification"
grep -F 'fail "Could not verify that Omarchy migrations completed.' <<<"$migrations_body" >/dev/null ||
  fail "Omarchy 4 upgrade fails when it cannot verify migration state"
if grep -F 'return 0' <<<"$migrations_body" >/dev/null || grep -F 'warn ' <<<"$migrations_body" >/dev/null; then
  fail "Omarchy 4 upgrade does not continue past failed migrations"
fi

exercise_post_upgrade_migrations() {
  local stub_migration_status="$1" stub_pending_status="$2"

  (
    log() { :; }
    fail() { exit 1; }
    run_as_user_omarchy() {
      if [[ " $* " == *" --pending "* ]]; then
        return "$stub_pending_status"
      else
        return "$stub_migration_status"
      fi
    }
    eval "run_post_upgrade_migrations() { $migrations_body
}"
    run_post_upgrade_migrations
  )
}

exercise_post_upgrade_migrations 0 1 >/dev/null 2>&1 ||
  fail "Omarchy 4 upgrade accepts a completed migration queue"
if exercise_post_upgrade_migrations 1 1 >/dev/null 2>&1; then
  fail "Omarchy 4 upgrade accepts a failed migration"
fi
if exercise_post_upgrade_migrations 0 0 >/dev/null 2>&1; then
  fail "Omarchy 4 upgrade accepts pending migrations"
fi
if exercise_post_upgrade_migrations 0 2 >/dev/null 2>&1; then
  fail "Omarchy 4 upgrade accepts a failed pending-state check"
fi
pass "Omarchy 4 upgrade cannot finish with pending migrations"

if function_body cleanup_retired_services | grep -F 'systemctl disable iwd' >/dev/null; then
  fail "Omarchy 4 upgrade does not retire iwd in a step separate from the NetworkManager enable"
fi
grep -A1 -F '  enable_system_service NetworkManager.service' "$upgrade_to_quattro" |
  grep -F 'as_root systemctl disable iwd.service' >/dev/null ||
  fail "Omarchy 4 upgrade retires iwd in the step that enables NetworkManager"
pass "Omarchy 4 upgrade switches from iwd to NetworkManager atomically"

# set -e aborts silently, so only an explicit banner distinguishes a
# half-upgraded system from a finished one.
grep -Fx 'trap cleanup_on_exit EXIT' "$upgrade_to_quattro" >/dev/null ||
  fail "Omarchy 4 upgrade reports an aborted run instead of exiting silently"
cleanup_body=$(function_body cleanup_on_exit)
grep -F 'upgrade_started && ! upgrade_completed' <<<"$cleanup_body" >/dev/null ||
  fail "Omarchy 4 upgrade reports an aborted run instead of exiting silently"
grep -F 'Upgrade incomplete - do NOT reboot.' <<<"$cleanup_body" >/dev/null ||
  fail "Omarchy 4 upgrade reports an aborted run instead of exiting silently"
grep -F 'exit "$exit_status"' <<<"$cleanup_body" >/dev/null ||
  fail "Omarchy 4 upgrade preserves the failing exit status"
grep -F '>&2' <<<"$cleanup_body" >/dev/null ||
  fail "Omarchy 4 upgrade reports an aborted run on stderr"
started_line=$(grep -n '^upgrade_started=1$' "$upgrade_to_quattro" | cut -d: -f1)
completed_line=$(grep -n '^upgrade_completed=1$' "$upgrade_to_quattro" | cut -d: -f1)
suppress_line=$(grep -n '^suppress_hyprland_config_reload$' "$upgrade_to_quattro" | cut -d: -f1)
# The reboot is the cutover, so the last mutating step hands the live session
# back rather than swapping the shell out underneath it.
last_step_line=$(grep -n '^restore_hyprland_config_reload$' "$upgrade_to_quattro" | cut -d: -f1)
[[ -n $started_line && -n $completed_line && -n $suppress_line && -n $last_step_line ]] ||
  fail "upgrade progress markers and the mutating step range exist"
(( started_line < suppress_line )) || fail "the upgrade is marked started before the first mutation"
(( completed_line > last_step_line )) || fail "the upgrade is marked complete only after the last step"
pass "Omarchy 4 upgrade reports an aborted run instead of exiting silently"

# Ordering alone would still pass if either retired entry point came back, so
# name them: the reboot is the cutover, and nothing may swap the shell out from
# under the session being replaced.
! grep -q 'start_omarchy_shell_session' "$upgrade_to_quattro" ||
  fail "Omarchy 4 upgrade does not start the shell in the session it is replacing"
! grep -q 'stop_retired_session_processes' "$upgrade_to_quattro" ||
  fail "Omarchy 4 upgrade leaves the retired session processes running until reboot"
pass "Omarchy 4 upgrade leaves the Omarchy 3 session alone until the reboot"

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
