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
icons_dir="$tmp_dir/home/.local/share/icons/hicolor/256x256/apps"

# A URL typed into the name field is the reported way in. Every slash used to
# become a directory level, leaving a launcher nothing could address. Assert on
# the message: creating the launcher directly in the applications directory
# already makes the redirect fail on its own, so a bare non-zero exit would pass
# just as well with no validation at all.
output=$(run_install "http://example.test/oops" "https://example.com" hey 2>&1) &&
  fail "webapp install rejects a name containing a slash"
[[ $output == *"App name cannot contain '/'"* ]] ||
  fail "webapp install says why it refused a slashed name" "$output"
[[ -e "$apps_dir/http:" ]] &&
  fail "webapp install does not create a directory from a slashed name"
pass "webapp install rejects a name that would nest the launcher"

# The name was a path fragment until something said otherwise, so ../ climbed
# out of the applications directory entirely and wrote wherever it landed.
if run_install "../../../../escaped" "https://example.com" hey >/dev/null 2>&1; then
  fail "webapp install rejects a name that climbs out of the applications directory"
fi
[[ -e "$tmp_dir/escaped.desktop" ]] &&
  fail "webapp install writes no launcher outside the applications directory"
pass "webapp install refuses a name that would escape the applications directory"

# The interactive prompt reads the name long before it is used as a path, and
# fetches the site icon in between. Rejecting only at the write leaves that icon
# behind in the user's icon theme, once per attempt.
mkdir -p "$tmp_dir/ibin"
cp "$tmp_dir/bin"/* "$tmp_dir/ibin/"
cat >"$tmp_dir/ibin/gum" <<'STUB'
#!/bin/bash
count_file="${GUM_STUB_COUNT:?}"
count=$(cat "$count_file" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" >"$count_file"
if (( count == 1 )); then
  echo "http://example.test/oops"
else
  echo "https://example.com"
fi
STUB
cat >"$tmp_dir/ibin/curl" <<'STUB'
#!/bin/bash
# Answer any download with a real PNG so the icon fetch reports success.
out=""
prev=""
for arg in "$@"; do
  [[ $prev == "-o" ]] && out="$arg"
  prev="$arg"
done
if [[ -n $out ]]; then
  printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | base64 -d >"$out"
fi
STUB
chmod +x "$tmp_dir/ibin/gum" "$tmp_dir/ibin/curl"

if HOME="$tmp_dir/home" PATH="$tmp_dir/ibin:$PATH" \
  GUM_STUB_COUNT="$tmp_dir/gum-count" \
  "$ROOT/bin/omarchy-webapp-install" >/dev/null 2>&1; then
  fail "interactive webapp install rejects a name containing a slash"
fi
if compgen -G "$icons_dir/*.png" >/dev/null; then
  fail "interactive webapp install downloads no icon for a name it refuses" \
    "$(ls "$icons_dir")"
fi
pass "webapp install refuses a slashed name before fetching its icon"

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

# Removing by name on a machine with no applications directory yet must stay
# quiet: omarchy-remove-gaming-xbox-cloud calls it without hiding stderr.
noise=$(HOME="$tmp_dir/empty" PATH="$tmp_dir/bin:$PATH" OMARCHY_REMOVE_NOTIFY=false \
  "$ROOT/bin/omarchy-webapp-remove" "Xbox Cloud Gaming" 2>&1 >/dev/null)
[[ -n $noise ]] &&
  fail "webapp remove stays quiet with no applications directory" "$noise"
pass "webapp remove stays quiet when there is no applications directory"
