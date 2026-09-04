#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

setup_script="$ROOT/install/user/xdg-desktop-portal.sh"
migration="$ROOT/migrations/1787508122.sh"

fresh=$(mktemp -d)
legacy=$(mktemp -d)
busless=$(mktemp -d)
xdg_home=$(mktemp -d)
trap 'rm -rf "$fresh" "$legacy" "$busless" "$xdg_home"' EXIT

# Keep each case isolated and use non-default XDG paths so the test proves the
# setup script honours the base-directory variables instead of hard-coding HOME.
run_in_home() {
  local home="$1"
  shift
  env \
    HOME="$home" \
    XDG_CONFIG_HOME="$home/xdg-config" \
    XDG_DATA_HOME="$home/xdg-data" \
    "$@"
}

assert_generated() {
  local home="$1" label="$2"
  local conf="$home/xdg-config/xdg-desktop-portal/hyprland-portals.conf"
  local portal="$home/xdg-data/xdg-desktop-portal/portals/nautilus.portal"
  local service="$home/xdg-data/dbus-1/services/org.gnome.Nautilus.service"

  grep -Fx 'org.freedesktop.impl.portal.FileChooser=nautilus' "$conf" >/dev/null ||
    fail "$label: Nautilus is selected for file chooser requests"
  grep -Fx 'default=hyprland;gtk' "$conf" >/dev/null ||
    fail "$label: Hyprland and GTK remain the default portal backends"
  grep -Fx 'DBusName=org.gnome.Nautilus' "$portal" >/dev/null ||
    fail "$label: portal descriptor names the Nautilus D-Bus service"
  grep -Fx 'Interfaces=org.freedesktop.impl.portal.FileChooser' "$portal" >/dev/null ||
    fail "$label: portal descriptor exposes only the file chooser"
  if grep -q 'UseIn' "$portal"; then
    fail "$label: portal descriptor does not carry the deprecated UseIn key"
  fi
  grep -Fx 'Exec=/usr/bin/env GDK_DEBUG=no-portals ADW_DISABLE_PORTAL=1 /usr/bin/nautilus --gapplication-service' "$service" >/dev/null ||
    fail "$label: Nautilus activation disarms both synchronous portal callers"
}

# A stub that records how it was called, so the migration's service reload and
# portal restart can be asserted exactly.
install_recording_systemctl() {
  local dir="$1/stub"
  mkdir -p "$dir"
  cat >"$dir/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
STUB
  chmod +x "$dir/systemctl"
  printf '%s\n' "$dir"
}

# 1. Fresh install.
run_in_home "$fresh" bash -euo pipefail "$setup_script"
assert_generated "$fresh" "fresh install"
pass "fresh installs route file chooser requests to Nautilus"

# 2. An explicit user preference survives a re-run.
fresh_conf="$fresh/xdg-config/xdg-desktop-portal/hyprland-portals.conf"
printf '%s\n' \
  '[preferred]' \
  'default=hyprland;gtk' \
  'org.freedesktop.impl.portal.FileChooser=custom' >"$fresh_conf"

run_in_home "$fresh" bash -euo pipefail "$setup_script"

grep -Fx 'org.freedesktop.impl.portal.FileChooser=custom' "$fresh_conf" >/dev/null ||
  fail "Existing file chooser preference is preserved"
chooser_count=$(grep -c '^org\.freedesktop\.impl\.portal\.FileChooser=' "$fresh_conf")
((chooser_count == 1)) || fail "File chooser preference is not duplicated"
pass "explicit user portal preferences are preserved"

# 2b. A [preferred] header with stray whitespace must not gain a second section.
printf '%s\n' '  [preferred]  ' 'default=hyprland;gtk' >"$fresh_conf"
run_in_home "$fresh" bash -euo pipefail "$setup_script"
section_count=$(grep -cE '^[[:space:]]*\[preferred\]' "$fresh_conf")
((section_count == 1)) || fail "A whitespace-padded [preferred] header is not duplicated"
grep -Fx 'org.freedesktop.impl.portal.FileChooser=nautilus' "$fresh_conf" >/dev/null ||
  fail "A whitespace-padded [preferred] section still receives the file chooser line"
pass "a whitespace-padded [preferred] section is amended, not duplicated"

# 2c. GKeyFile allows whitespace around the separator, so a hand-written config
# may well use it. Missing that form inserts a second FileChooser key; GKeyFile
# resolves a duplicate key to the last occurrence, so the user's backend keeps
# winning and the routing this script exists to apply silently never happens.
printf '%s\n' '[preferred]' 'default = hyprland;gtk' \
  'org.freedesktop.impl.portal.FileChooser = kde' >"$fresh_conf"
run_in_home "$fresh" bash -euo pipefail "$setup_script"
chooser_count=$(grep -cE '^[[:space:]]*org\.freedesktop\.impl\.portal\.FileChooser[[:space:]]*=' "$fresh_conf")
((chooser_count == 1)) || fail "A spaced file chooser preference is not duplicated"
grep -Fx 'org.freedesktop.impl.portal.FileChooser = kde' "$fresh_conf" >/dev/null ||
  fail "A spaced file chooser preference is preserved"
pass "a preference written with spaces around the separator is preserved"

# 2d. An empty portals.conf. `sed 1i` is a line address and inserts nothing into
# a zero-line file, so a plain -e existence check leaves the file untouched.
: >"$fresh_conf"
run_in_home "$fresh" bash -euo pipefail "$setup_script"
grep -Fx 'org.freedesktop.impl.portal.FileChooser=nautilus' "$fresh_conf" >/dev/null ||
  fail "An empty portal preference file is populated"
pass "an empty portals.conf is populated rather than left untouched"

# Unset XDG dirs: files must land in the $HOME defaults.
HOME="$xdg_home" env -u XDG_CONFIG_HOME -u XDG_DATA_HOME bash -euo pipefail "$setup_script"
[[ -e $xdg_home/.config/xdg-desktop-portal/hyprland-portals.conf ]] ||
  fail "without XDG overrides, portal preference is written under ~/.config"
[[ -e $xdg_home/.local/share/xdg-desktop-portal/portals/nautilus.portal ]] ||
  fail "without XDG overrides, portal descriptor is written under ~/.local/share"
[[ -e $xdg_home/.local/share/dbus-1/services/org.gnome.Nautilus.service ]] ||
  fail "without XDG overrides, Nautilus D-Bus override is written under ~/.local/share"
pass "XDG defaults are used when XDG_CONFIG_HOME and XDG_DATA_HOME are unset"

# 3. The migration repairs a separate empty home and restarts the portal.
legacy_stub=$(install_recording_systemctl "$legacy")
run_in_home "$legacy" \
  PATH="$legacy_stub:$PATH" SYSTEMCTL_LOG="$legacy/systemctl.log" OMARCHY_PATH="$ROOT" \
  bash -euo pipefail "$migration" >/dev/null

assert_generated "$legacy" "migration"
grep -Fx -- '--user reload dbus-broker.service' "$legacy/systemctl.log" >/dev/null ||
  fail "migration reloads the D-Bus service registry"
grep -Fx -- '--user try-restart xdg-desktop-portal.service' "$legacy/systemctl.log" >/dev/null ||
  fail "migration restarts the portal frontend"
pass "existing installs apply the portal migration"

# 4. No user bus reachable: the migration must still succeed, or omarchy-migrate
# aborts the whole run and skips every later pending migration.
busless_stub="$busless/stub"
mkdir -p "$busless_stub"
printf '%s\n' '#!/bin/bash' 'echo "Failed to connect to bus: No medium found" >&2' 'exit 1' \
  >"$busless_stub/systemctl"
chmod +x "$busless_stub/systemctl"

run_in_home "$busless" PATH="$busless_stub:$PATH" OMARCHY_PATH="$ROOT" \
  bash -euo pipefail "$migration" >/dev/null ||
  fail "migration tolerates an unreachable user bus"
assert_generated "$busless" "migration without a user bus"
pass "the migration does not abort when no user bus is reachable"
