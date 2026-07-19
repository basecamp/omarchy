#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

template="$ROOT/default/snapper/root"
limine_defaults="$ROOT/etc/limine-entry-tool.d/omarchy-defaults.conf"
limine_notify_autostart="$ROOT/config/autostart/limine-snapper-notify.desktop"

grep -Fx 'NUMBER_CLEANUP="yes"' "$template" >/dev/null
grep -Fx 'NUMBER_LIMIT="5"' "$template" >/dev/null
grep -Fx 'TIMELINE_CREATE="no"' "$template" >/dev/null
! grep -Eq '^TIMELINE_(CLEANUP|LIMIT_)' "$template" || fail "Snapper template keeps timeline cleanup details out of the default config"
grep -Fx 'MAX_SNAPSHOT_ENTRIES=6' "$limine_defaults" >/dev/null || fail "Limine allows for a snapshot created before Snapper cleanup"
pass "Snapper and Limine retain update snapshots without a transient limit mismatch"

grep -Fx '[Desktop Entry]' "$limine_notify_autostart" >/dev/null
grep -Fx 'Hidden=true' "$limine_notify_autostart" >/dev/null
pass "Limine Snapper warning notifier is disabled by default"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/snapper" <<'STUB'
#!/bin/bash
printf 'snapper %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin/snapper"

cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin/systemctl"

notification_migration=$(grep -rl 'Disable Limine Snapper warning notifier' "$ROOT/migrations" | head -n 1 || true)
[[ -n $notification_migration ]] || fail "Limine Snapper warning notifier migration exists"
grep -F 'limine-snapper-notify.desktop' "$notification_migration" >/dev/null
grep -F 'systemctl --user daemon-reload' "$notification_migration" >/dev/null
grep -F "app-limine\\x2dsnapper\\x2dnotify@autostart.service" "$notification_migration" >/dev/null

migration_home="$test_tmp/migration-home"
mkdir -p "$migration_home"
TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
HOME="$migration_home" \
  bash -euo pipefail "$notification_migration" >/dev/null

cmp -s "$limine_notify_autostart" "$migration_home/.config/autostart/limine-snapper-notify.desktop" || fail "Limine Snapper warning notifier migration writes autostart override"
grep -Fx 'systemctl --user daemon-reload' "$test_tmp/calls.log" >/dev/null || fail "Limine Snapper warning notifier migration reloads user units"
grep -Fx 'systemctl --user stop app-limine\x2dsnapper\x2dnotify@autostart.service' "$test_tmp/calls.log" >/dev/null || fail "Limine Snapper warning notifier migration stops active watcher"
pass "Limine Snapper warning notifier migration disables existing user autostart"

: >"$test_tmp/calls.log"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_SNAPPER_CONFIGURE_TEST=1 \
OMARCHY_PATH="$ROOT" \
OMARCHY_SNAPPER_CONFIG_PATH="$test_tmp/etc/snapper/configs/root" \
OMARCHY_SNAPPER_CONF_PATH="$test_tmp/etc/conf.d/snapper" \
  bash -euo pipefail "$ROOT/install/config/snapper.sh" >/dev/null

cmp -s "$template" "$test_tmp/etc/snapper/configs/root" || fail "snapshot configure installs the Omarchy Snapper template"
grep -Fx 'SNAPPER_CONFIGS="root"' "$test_tmp/etc/conf.d/snapper" >/dev/null || fail "snapshot configure writes /etc/conf.d/snapper"
grep -Fx 'systemctl disable --now snapper-timeline.timer' "$test_tmp/calls.log" >/dev/null || fail "snapshot configure disables timeline snapshots"
grep -Fx 'systemctl enable --now snapper-cleanup.timer limine-snapper-sync.service' "$test_tmp/calls.log" >/dev/null || fail "snapshot configure enables cleanup and Limine snapshot sync"
pass "snapshot configure normalizes Snapper policy and services"

setup_system="$ROOT/bin/omarchy-setup-system"
grep -F 'config/snapper.sh' "$setup_system" >/dev/null
pass "system setup normalizes Snapper during fresh installs"

migration=$(grep -rl 'Normalize Snapper snapshot services' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "Snapper service migration exists"
grep -F 'unit_active snapper-cleanup.timer' "$migration" >/dev/null
grep -F 'unit_active limine-snapper-sync.service' "$migration" >/dev/null
grep -F 'sudo "$@"' "$migration" >/dev/null
grep -F 'as_root env OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail "$snapper_config_script"' "$migration" >/dev/null
! grep -F 'NUMBER_LIMIT="5"' "$migration" >/dev/null || fail "Snapper service migration does not overwrite working custom retention"
pass "Snapper service migration only repairs broken services idempotently"

find_omarchy_pks_root() {
  local candidate
  for candidate in \
    "$ROOT/../omarchy-pkgs/pkgbuilds" \
    "$ROOT/../omarchy/omarchy-pkgs/pkgbuilds" \
    "$ROOT/../../omarchy-pkgs/pkgbuilds"; do
    if [[ -d $candidate ]]; then
      cd "$candidate" && pwd
      return 0
    fi
  done
  return 1
}

pkgs_root=$(find_omarchy_pks_root) || fail "omarchy-pkgs checkout is available for packaging coverage"
settings_pkgbuild="$pkgs_root/omarchy-settings-dev/PKGBUILD"
omarchy_pkgbuild="$pkgs_root/omarchy-dev/PKGBUILD"

grep -F 'cp -a default/. "$pkgdir/usr/share/omarchy/default/"' "$settings_pkgbuild" >/dev/null || fail "omarchy-settings package bundles default/"
grep -F 'install -Dm644 default/snapper/root \' "$settings_pkgbuild" >/dev/null || fail "omarchy-settings package installs Snapper template source"
grep -F '"$pkgdir/etc/snapper/config-templates/omarchy"' "$settings_pkgbuild" >/dev/null || fail "omarchy-settings package installs Snapper template destination"
grep -F "'snapper'" "$omarchy_pkgbuild" >/dev/null || fail "omarchy package depends on snapper"
grep -F "'limine-snapper-sync'" "$omarchy_pkgbuild" >/dev/null || fail "omarchy package depends on limine-snapper-sync"
grep -F 'cp -a install "$pkgdir/usr/share/omarchy/"' "$omarchy_pkgbuild" >/dev/null || fail "omarchy package bundles install scripts"
grep -F 'cp -a migrations "$pkgdir/usr/share/omarchy/"' "$omarchy_pkgbuild" >/dev/null || fail "omarchy package bundles migrations"
pass "omarchy-pkgs packages Snapper template, setup, and migration coverage"

find_omarchy_iso_root() {
  local candidate
  for candidate in \
    "$ROOT/../omarchy-iso" \
    "$ROOT/../omarchy/omarchy-iso" \
    "$ROOT/../../omarchy-iso"; do
    if [[ -d $candidate ]]; then
      cd "$candidate" && pwd
      return 0
    fi
  done
  return 1
}

iso_root=$(find_omarchy_iso_root) || fail "omarchy-iso checkout is available for installer coverage"
configurator="$iso_root/configs/airootfs/root/configurator"
phases="$iso_root/configs/airootfs/usr/share/omarchy-iso/orchestrator/phases_impl.py"
manifest="$iso_root/manifests/fresh-4-semantic.json"

! grep -F 'snapshot_config' "$configurator" >/dev/null || fail "ISO does not ask archinstall to create Snapper timeline config"

# The phases/manifest assertions cover the newer ISO orchestrator structure.
# Skip them when the checkout predates that layout.
if [[ -f $phases && -f $manifest ]]; then
  ! grep -F '_configure_snapper_root' "$phases" >/dev/null || fail "ISO does not duplicate Omarchy Snapper setup"
  grep -F 'run_system_finalizer' "$phases" >/dev/null || fail "ISO runs packaged system setup"
  grep -F '/etc/systemd/system/timers.target.wants/snapper-cleanup.timer' "$manifest" >/dev/null || fail "fresh ISO manifest has snapper-cleanup timer enabled"
  ! grep -F '/etc/systemd/system/timers.target.wants/snapper-timeline.timer' "$manifest" >/dev/null || fail "fresh ISO manifest does not enable snapper timeline timer"
fi
pass "omarchy-iso delegates Snapper setup to packaged system setup"
