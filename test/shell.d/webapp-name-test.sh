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

# The picker and a caller hand the remover the same kind of string and mean
# different things by it, so the no-argument path has to be driven as itself
# rather than imitated with an argument. The stub returns whatever was picked.
printf '#!/bin/bash\nprintf "%%s\\n" "$PICK"\n' >"$tmp_dir/bin/omarchy-menu-select"
chmod +x "$tmp_dir/bin/omarchy-menu-select"

run_pick() {
  HOME="$tmp_dir/home" PATH="$tmp_dir/bin:$PATH" OMARCHY_REMOVE_NOTIFY=false PICK="$1" \
    "$ROOT/bin/omarchy-webapp-remove"
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
run_pick "127.0.0.1:4000" >/dev/null
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

# omarchy-remove-launcher-entry hands back the basename of a top-level launcher
# it just found, so an explicit name has to keep meaning that file. The
# top-level entry here is deliberately not a web app: that keeps it out of the
# index, so the outcome does not depend on the order find walked the directory.
rm -rf "$apps_dir"
mkdir -p "$apps_dir/legacy"
printf '[Desktop Entry]\nExec=foot\n' >"$apps_dir/Tailscale.desktop"
cat >"$apps_dir/legacy/Tailscale.desktop" <<'DESKTOP'
[Desktop Entry]
Exec=omarchy-launch-webapp https://unrelated.example
DESKTOP
run_remove "Tailscale" >/dev/null
[[ -f "$apps_dir/legacy/Tailscale.desktop" ]] ||
  fail "webapp remove leaves a nested launcher alone when it was given a top-level name"
[[ -f "$apps_dir/Tailscale.desktop" ]] &&
  fail "webapp remove deletes the top-level launcher an explicit name asks for"
pass "webapp remove addresses the top-level launcher an explicit name asks for"

# The same two files, reached the other way. The picker only ever offered the
# nested web app -- the top-level entry is not one and was never in the list --
# so picking that name has to delete what was shown rather than what shares its
# name in the applications directory.
rm -rf "$apps_dir"
mkdir -p "$apps_dir/legacy"
printf '[Desktop Entry]\nExec=foot\n' >"$apps_dir/Tailscale.desktop"
cat >"$apps_dir/legacy/Tailscale.desktop" <<'DESKTOP'
[Desktop Entry]
Exec=omarchy-launch-webapp https://unrelated.example
DESKTOP
run_pick "Tailscale" >/dev/null
[[ -f "$apps_dir/legacy/Tailscale.desktop" ]] &&
  fail "webapp remove deletes the launcher the picker offered"
[[ -f "$apps_dir/Tailscale.desktop" ]] ||
  fail "webapp remove leaves alone a launcher the picker never offered"
pass "webapp remove deletes the file behind the name the picker showed"

# The picker parses a tab in an option as its own separator, so a name it hands
# back is not guaranteed to be one the scan indexed. Rebuilding a top-level path
# from a name that cannot be placed deletes whatever happens to sit there.
rm -rf "$apps_dir"
mkdir -p "$apps_dir/legacy"
printf '[Desktop Entry]\nExec=foot\n' >"$apps_dir/Victim.desktop"
cat >"$apps_dir/legacy/Real.desktop" <<'DESKTOP'
[Desktop Entry]
Exec=omarchy-launch-webapp https://real.example
DESKTOP
run_pick "Victim" >/dev/null 2>&1 &&
  fail "webapp remove refuses a picked name the scan never indexed"
[[ -f "$apps_dir/Victim.desktop" ]] ||
  fail "webapp remove deletes nothing when it cannot place the picked name"
pass "webapp remove refuses a picked name the scan never indexed"

# Reaching the picker at all is the menu's decision, and a launcher an older
# install nested is exactly the one a non-recursive glob cannot see. Take the
# guard from the menu definition rather than restating it, so the two cannot
# drift apart.
webapp_menu_guard=$(grep -o '"remove\.webapp":.*' "$ROOT/default/omarchy/omarchy-menu.jsonc" |
  sed 's/.*"when":"//; s/","action".*//')
[[ -n $webapp_menu_guard ]] ||
  fail "the menu definition still has a when guard on Remove > Web App"

rm -rf "$apps_dir"
mkdir -p "$apps_dir/http:/127.0.0.1:4000"
cat >"$apps_dir/http:/127.0.0.1:4000/.desktop" <<'DESKTOP'
[Desktop Entry]
Exec=omarchy-launch-webapp https://127.0.0.1:4000
DESKTOP
HOME="$tmp_dir/home" PATH="$ROOT/bin:$PATH" bash -c "$webapp_menu_guard" ||
  fail "the Remove menu offers Web App when the only launcher is a nested one"
pass "the Remove menu reaches a launcher an older install nested"

# And still hides the row when there is nothing to remove, so the guard has not
# simply been widened into always-true.
rm -rf "$apps_dir"
mkdir -p "$apps_dir"
printf '[Desktop Entry]\nExec=foot\n' >"$apps_dir/foot.desktop"
HOME="$tmp_dir/home" PATH="$ROOT/bin:$PATH" bash -c "$webapp_menu_guard" &&
  fail "the Remove menu hides Web App when no launcher is a web app"
pass "the Remove menu hides Web App when there is none"

# A launcher can be a symlink, and the remover's own scan reads one, so the menu
# has to see it too -- a guard that misses it hides a row for something that is
# sitting there removable.
rm -rf "$apps_dir" "$tmp_dir/elsewhere"
mkdir -p "$apps_dir" "$tmp_dir/elsewhere"
cat >"$tmp_dir/elsewhere/Linked.desktop" <<'DESKTOP'
[Desktop Entry]
Exec=omarchy-launch-webapp https://linked.example
DESKTOP
ln -s "$tmp_dir/elsewhere/Linked.desktop" "$apps_dir/Linked.desktop"
HOME="$tmp_dir/home" PATH="$ROOT/bin:$PATH" bash -c "$webapp_menu_guard" ||
  fail "the Remove menu sees a launcher that is a symlink"
pass "the Remove menu sees a symlinked launcher"

# A predicate answers with its exit status, so a launcher it cannot read is not
# something to say anything about: omarchy-webapp-present is run directly as
# `omarchy webapp present`, where find's silence would not cover grep's.
rm -rf "$apps_dir"
mkdir -p "$apps_dir"
printf '[Desktop Entry]\nExec=foot\n' >"$apps_dir/unreadable.desktop"
chmod 000 "$apps_dir/unreadable.desktop"
guard_noise=$(HOME="$tmp_dir/home" "$ROOT/bin/omarchy-webapp-present" 2>&1 >/dev/null || true)
chmod 644 "$apps_dir/unreadable.desktop"
[[ -n $guard_noise ]] &&
  fail "omarchy-webapp-present stays quiet about a launcher it cannot read" "$guard_noise"
pass "omarchy-webapp-present stays quiet about a launcher it cannot read"
