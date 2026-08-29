#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
export PATH="$ROOT/bin:$PATH"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
next_theme="$home/.local/state/omarchy/current/next-theme"
current_theme="$home/.local/state/omarchy/current/theme"
mkdir -p "$next_theme" "$current_theme"

cat >"$next_theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"
background = "#1a1b26"
dark_background = "#13141c"
darker_background = "#0e0e14"
lighter_background = "#24283b"
foreground = "#a9b1d6"
dark_foreground = "#565f89"
red = "#330000"
yellow = "#e0af68"
green = "#9ece6a"
cyan = "#449dab"
TOML

HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-theme-set-templates"
css="$next_theme/gtk.css"
[[ -f $css ]] || fail "GTK template is generated"
grep -Fq -- '--accent-bg-color: #7aa2f7;' "$css" || fail "GTK accent follows the theme"
grep -Fq -- '--accent-fg-color: #1a1b26;' "$css" || fail "GTK accent uses the theme background for contrast"
grep -Fq -- '--destructive-fg-color: #1a1b26;' "$css" || fail "GTK destructive actions use the theme background"
grep -Fq -- '--success-fg-color: #1a1b26;' "$css" || fail "GTK success actions use the theme background"
grep -Fq -- '--warning-fg-color: #1a1b26;' "$css" || fail "GTK warnings use the theme background"
grep -Fq -- '--overview-bg-color: #13141c;' "$css" || fail "GTK overview surface is themed"
grep -Fq -- '--active-toggle-bg-color: #7aa2f7;' "$css" || fail "GTK active toggle is themed"
grep -Fq -- '@media (prefers-color-scheme: dark)' "$css" || fail "GTK palette follows the theme mode"
grep -Fq -- '@define-color window_bg_color #1a1b26;' "$css" || fail "GTK compatibility colors follow the theme"
grep -q '{{' "$css" && fail "GTK template has no unresolved values"

for name in \
  accent-bg accent-fg destructive-bg destructive-fg success-bg success-fg \
  warning-bg warning-fg error-bg error-fg window-bg window-fg view-bg view-fg \
  headerbar-bg headerbar-fg headerbar-backdrop sidebar-bg sidebar-fg \
  sidebar-backdrop secondary-sidebar-bg secondary-sidebar-fg \
  secondary-sidebar-backdrop card-bg card-fg dialog-bg dialog-fg popover-bg \
  popover-fg overview-bg overview-fg thumbnail-bg thumbnail-fg \
  active-toggle-bg active-toggle-fg; do
  grep -Fq -- "--${name}-color:" "$css" || fail "GTK template defines --${name}-color"
done

/usr/bin/python - "$css" <<'PY'
import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk

errors = []
provider = Gtk.CssProvider()
provider.connect(
    "parsing-error", lambda _provider, _section, error: errors.append(error.message)
)
provider.load_from_path(sys.argv[1])
if errors:
    raise SystemExit("\n".join(errors))
PY
pass "GTK template renders the complete libadwaita palette"

cp "$css" "$current_theme/gtk.css"
HOME="$home" XDG_CONFIG_HOME="$home/.config" OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-theme-set-gtk"

gtk_css="$home/.config/gtk-4.0/gtk.css"
omarchy_css="$home/.config/gtk-4.0/omarchy.css"
[[ $(<"$gtk_css") == '@import url("omarchy.css");' ]] || fail "GTK entrypoint imports the Omarchy theme"
[[ -L $omarchy_css ]] || fail "Omarchy GTK stylesheet is linked"
[[ $(readlink "$omarchy_css") == $current_theme/gtk.css ]] || fail "GTK stylesheet links to the current theme"
pass "GTK theme is installed for new GTK processes"

printf 'button { border-radius: 0; }\n' >>"$gtk_css"
HOME="$home" XDG_CONFIG_HOME="$home/.config" OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-theme-set-gtk"
[[ $(grep -Fxc '@import url("omarchy.css");' "$gtk_css") == 1 ]] || fail "GTK import is not duplicated"
grep -Fq 'button { border-radius: 0; }' "$gtk_css" || fail "GTK user CSS is preserved"
pass "GTK installation preserves user CSS"

rm "$current_theme/gtk.css"
HOME="$home" XDG_CONFIG_HOME="$home/.config" OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-theme-set-gtk"
grep -Fxq '/* Omarchy GTK theme unavailable. */' "$omarchy_css" || fail "missing theme CSS clears the managed stylesheet"
grep -Fq 'button { border-radius: 0; }' "$gtk_css" || fail "missing theme CSS keeps user CSS"
pass "GTK installation clears only Omarchy-owned state"

printf '/* user-owned omarchy.css */\n' >"$omarchy_css"
printf '/* replacement theme */\n' >"$current_theme/gtk.css"
HOME="$home" XDG_CONFIG_HOME="$home/.config" OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-theme-set-gtk"
grep -Fxq '/* user-owned omarchy.css */' "$omarchy_css" || fail "user-owned omarchy.css is preserved"
pass "GTK installation does not overwrite an unrelated omarchy.css"

PYTHONPYCACHEPREFIX="$test_tmp/pycache" python -m py_compile "$ROOT/default/nautilus-python/extensions/omarchy_theme.py"
pass "Nautilus extension is syntactically valid"

signal_bin="$test_tmp/signal-bin"
signal_log="$test_tmp/signal.log"
mkdir -p "$signal_bin"
cat >"$signal_bin/gdbus" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$SIGNAL_LOG"
SH
chmod +x "$signal_bin/gdbus"
rm "$omarchy_css"
HOME="$home" XDG_CONFIG_HOME="$home/.config" OMARCHY_PATH="$ROOT" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/test" SIGNAL_LOG="$signal_log" \
  PATH="$signal_bin:$PATH" "$ROOT/bin/omarchy-theme-set-gtk"
grep -Fq -- '--signal org.omarchy.Theme.Changed' "$signal_log" || fail "GTK theme changes notify Nautilus over D-Bus"
pass "GTK theme changes directly notify Nautilus"

rm "$signal_log"
HOME="$home" XDG_CONFIG_HOME="$home/.config" OMARCHY_PATH="$ROOT" \
  OMARCHY_THEME_OFFLINE=1 DBUS_SESSION_BUS_ADDRESS="unix:path=/test" \
  SIGNAL_LOG="$signal_log" PATH="$signal_bin:$PATH" "$ROOT/bin/omarchy-theme-set-gtk"
[[ ! -e $signal_log ]] || fail "offline GTK setup does not notify Nautilus"
pass "offline GTK setup only writes persistent config"

migration_home="$test_tmp/migration-home"
stub_bin="$test_tmp/bin"
migration_log="$test_tmp/migration.log"
mkdir -p "$migration_home" "$stub_bin"
cat >"$stub_bin/omarchy-theme-refresh" <<'SH'
#!/bin/bash
printf '%s\n' refresh >>"$MIGRATION_LOG"
SH
chmod +x "$stub_bin/omarchy-theme-refresh"

HOME="$migration_home" OMARCHY_PATH="$ROOT" MIGRATION_LOG="$migration_log" \
  PATH="$stub_bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787756628.sh" >/dev/null
HOME="$migration_home" OMARCHY_PATH="$ROOT" MIGRATION_LOG="$migration_log" \
  PATH="$stub_bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787756628.sh" >/dev/null
cmp -s \
  "$ROOT/default/nautilus-python/extensions/omarchy_theme.py" \
  "$migration_home/.local/share/nautilus-python/extensions/omarchy_theme.py" || \
  fail "GTK migration installs the Nautilus extension"
[[ $(grep -Fxc refresh "$migration_log") == 1 ]] || fail "GTK migration refreshes the active theme once"
pass "GTK migration installs live reload and refreshes the theme"

failed_refresh_home="$test_tmp/failed-refresh-home"
mkdir -p "$failed_refresh_home"
cat >"$stub_bin/omarchy-theme-refresh" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$stub_bin/omarchy-theme-refresh"
HOME="$failed_refresh_home" OMARCHY_PATH="$ROOT" \
  PATH="$stub_bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787756628.sh" >/dev/null
cmp -s \
  "$ROOT/default/nautilus-python/extensions/omarchy_theme.py" \
  "$failed_refresh_home/.local/share/nautilus-python/extensions/omarchy_theme.py" || \
  fail "GTK migration keeps the Nautilus extension when theme refresh fails"
pass "GTK migration does not lose live reload to an unrelated retint failure"

dangling_home="$test_tmp/dangling-home"
dangling_extension="$dangling_home/.local/share/nautilus-python/extensions/omarchy_theme.py"
mkdir -p "$(dirname "$dangling_extension")"
ln -s "$dangling_home/missing-extension.py" "$dangling_extension"
HOME="$dangling_home" OMARCHY_PATH="$ROOT" \
  PATH="$stub_bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787756628.sh" >/dev/null
[[ -L $dangling_extension ]] || fail "GTK migration preserves a dangling user extension symlink"
[[ $(readlink "$dangling_extension") == $dangling_home/missing-extension.py ]] || fail "GTK migration does not follow a dangling user extension symlink"
pass "GTK migration preserves user-managed extension symlinks"

echo "ok - omarchy GTK theming"
