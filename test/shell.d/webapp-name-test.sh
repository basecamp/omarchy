#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/home"

for stub in gtk-update-icon-cache update-desktop-database omarchy-notification-send; do
  printf '#!/bin/bash\n:\n' >"$tmp_dir/bin/$stub"
  chmod +x "$tmp_dir/bin/$stub"
done

run_install() {
  HOME="$tmp_dir/home" PATH="$tmp_dir/bin:$PATH" \
    "$ROOT/bin/omarchy-webapp-install" "$@"
}

run_remove() {
  HOME="$tmp_dir/home" PATH="$tmp_dir/bin:$PATH" OMARCHY_REMOVE_NOTIFY=false \
    "$ROOT/bin/omarchy-webapp-remove" "$@"
}

apps_dir="$tmp_dir/home/.local/share/applications"

# A URL typed into the name field is the reported way in. Every slash used to
# become a directory level, leaving a launcher nothing could address.
if run_install "http://example.test/oops" "https://example.com" hey >/dev/null 2>&1; then
  fail "webapp install rejects a name containing a slash"
fi
[[ -e "$apps_dir/http:" ]] &&
  fail "webapp install does not create a directory from a slashed name"
pass "webapp install rejects a name that would nest the launcher"

# A normal name still installs and removes.
run_install "Example App" "https://example.com" hey >/dev/null
[[ -f "$apps_dir/Example App.desktop" ]] ||
  fail "webapp install writes the launcher for an ordinary name"
run_remove "Example App" >/dev/null
[[ -f "$apps_dir/Example App.desktop" ]] &&
  fail "webapp remove deletes the launcher it installed"
pass "webapp install and remove round-trip an ordinary name"

# Anything installed by an older version can still be nested. Removal has to
# reach it, which a path rebuilt from the displayed name never could.
mkdir -p "$apps_dir/http:/127.0.0.1:4000"
cat >"$apps_dir/http:/127.0.0.1:4000/.desktop" <<'DESKTOP'
[Desktop Entry]
Name=http://127.0.0.1:4000
Exec=omarchy-launch-webapp https://127.0.0.1:4000
Type=Application
DESKTOP

# This is the name the picker shows for that file: the script strips .desktop
# from the path and then takes the basename, which lands on the directory.
run_remove "127.0.0.1:4000" >/dev/null
[[ -f "$apps_dir/http:/127.0.0.1:4000/.desktop" ]] &&
  fail "webapp remove deletes a launcher left nested by an older install"
pass "webapp remove reaches a nested legacy launcher"
