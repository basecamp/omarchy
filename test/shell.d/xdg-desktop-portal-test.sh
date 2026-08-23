#!/bin/bash

source "$(dirname "$0")/base-test.sh"

setup_script="$ROOT/install/user/xdg-desktop-portal.sh"
migration="$ROOT/migrations/1787508122.sh"
test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT

HOME="$test_home" bash -euo pipefail "$setup_script"

portal_config="$test_home/.config/xdg-desktop-portal/hyprland-portals.conf"
nautilus_portal="$test_home/.local/share/xdg-desktop-portal/portals/nautilus.portal"

grep -Fx 'org.freedesktop.impl.portal.FileChooser=nautilus' "$portal_config" >/dev/null || fail "Nautilus is selected for file chooser requests"
grep -Fx 'default=hyprland;gtk' "$portal_config" >/dev/null || fail "Hyprland and GTK remain the default portal backends"
grep -Fx 'DBusName=org.gnome.Nautilus' "$nautilus_portal" >/dev/null || fail "Nautilus portal descriptor names the Nautilus D-Bus service"
grep -Fx 'Interfaces=org.freedesktop.impl.portal.FileChooser' "$nautilus_portal" >/dev/null || fail "Nautilus portal descriptor exposes only the file chooser"
pass "fresh installs route file chooser requests to Nautilus"

printf '%s\n' \
  '[preferred]' \
  'default=hyprland;gtk' \
  'org.freedesktop.impl.portal.FileChooser=custom' >"$portal_config"

HOME="$test_home" bash -euo pipefail "$setup_script"

grep -Fx 'org.freedesktop.impl.portal.FileChooser=custom' "$portal_config" >/dev/null || fail "Existing file chooser preference is preserved"
[[ $(grep -c '^org\.freedesktop\.impl\.portal\.FileChooser=' "$portal_config") -eq 1 ]] || fail "File chooser preference is not duplicated"
pass "explicit user portal preferences are preserved"

stub_bin="$test_home/bin"
mkdir -p "$stub_bin"
printf '%s\n' '#!/bin/bash' 'exit 0' >"$stub_bin/systemctl"
chmod +x "$stub_bin/systemctl"

HOME="$test_home" PATH="$stub_bin:$PATH" OMARCHY_PATH="$ROOT" bash -euo pipefail "$migration" >/dev/null
pass "existing installs apply the portal migration"
