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
    "$ROOT/bin/omarchy-tui-install" "$@"
}

run_remove() {
  HOME="$tmp_dir/home" PATH="$tmp_dir/bin:$PATH" OMARCHY_REMOVE_NOTIFY=false \
    "$ROOT/bin/omarchy-tui-remove" "$@"
}

apps_dir="$tmp_dir/home/.local/share/applications"

# A URL typed into the name field is the reported way in. Every slash used to
# become a directory level, leaving a launcher nothing could address. Assert on
# the message: creating the launcher directly in the applications directory
# already makes the path failure indistinguishable from no validation at all.
output=$(run_install "http://example.test/oops" "lazydocker" tile hey 2>&1) &&
  fail "tui install rejects a name containing a slash"
[[ $output == *"App name cannot contain '/'"* ]] ||
  fail "tui install says why it refused a slashed name" "$output"
[[ -e "$apps_dir/http:" ]] &&
  fail "tui install does not create a directory from a slashed name"
pass "tui install rejects a name that would nest the launcher"

# The name was a path fragment until something said otherwise, so ../ climbed
# out of the applications directory entirely and wrote wherever it landed.
if run_install "../../../../escaped" "lazydocker" tile hey >/dev/null 2>&1; then
  fail "tui install rejects a name that climbs out of the applications directory"
fi
[[ -e "$tmp_dir/escaped.desktop" ]] &&
  fail "tui install writes no launcher outside the applications directory"
pass "tui install refuses a name that would escape the applications directory"

# The interactive prompt reads the name first, so refusal has to happen right
# then rather than after the window-style pick and icon questions.
mkdir -p "$tmp_dir/ibin"
cp "$tmp_dir/bin"/* "$tmp_dir/ibin/"
cat >"$tmp_dir/ibin/gum" <<'STUB'
#!/bin/bash
count=$(cat "$GUM_STUB_COUNT" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" >"$GUM_STUB_COUNT"
sed -n "${count}p" "$GUM_ANSWERS"
STUB
chmod +x "$tmp_dir/ibin/gum"

printf 'http://example.test/oops\n' >"$tmp_dir/answers"
: >"$tmp_dir/gum-count"
if HOME="$tmp_dir/home" PATH="$tmp_dir/ibin:$PATH" GUM_STUB_COUNT="$tmp_dir/gum-count" \
  GUM_ANSWERS="$tmp_dir/answers" "$ROOT/bin/omarchy-tui-install" >/dev/null 2>&1; then
  fail "interactive tui install rejects a name containing a slash"
fi
[[ $(cat "$tmp_dir/gum-count") == 1 ]] ||
  fail "interactive tui install refuses the name before asking the next question"
pass "interactive tui install refuses a slashed name before any launcher work"

# The property the escaping exists for: a newline in a value must not be able to
# start a second key line, in the Name field or anywhere else -- the Exec line
# included.
inject_name=$(printf 'Inject\nExec=evil')
run_install "$inject_name" "lazydocker" tile hey >/dev/null
inject_file="$apps_dir/$inject_name.desktop"
[[ -f $inject_file ]] ||
  fail "tui install writes a desktop entry for a name containing a newline"
(( $(grep -c '^Exec=' "$inject_file") == 1 )) ||
  fail "a newline in the name cannot inject a second Exec" "$(cat "$inject_file")"
grep -Fqx 'Name=Inject\nExec=evil' "$inject_file" ||
  fail "a newline in the name is escaped in the Name field" "$(cat "$inject_file")"
pass "tui install escapes newlines instead of writing a second Exec"

# A normal name still installs and removes.
run_install "Example App" "lazydocker" tile hey >/dev/null
[[ -f "$apps_dir/Example App.desktop" ]] ||
  fail "tui install writes the launcher for an ordinary name"
grep -Fqx 'Exec=xdg-terminal-exec --app-id=TUI.tile -e lazydocker' "$apps_dir/Example App.desktop" ||
  fail "tui install writes the launch command" "$(cat "$apps_dir/Example App.desktop")"
run_remove "Example App" >/dev/null
[[ -f "$apps_dir/Example App.desktop" ]] &&
  fail "tui remove deletes the launcher it installed"
pass "tui install and remove round-trip an ordinary name"

# Anything installed by an older version can still be nested. Removal has to
# reach it, which a path rebuilt from the displayed name never could.
mkdir -p "$apps_dir/legacy/sub"
cat >"$apps_dir/legacy/sub/Nested.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Nested
Exec=xdg-terminal-exec --app-id=TUI.tile -e lazydocker
Type=Application
DESKTOP

run_remove "Nested" >/dev/null
[[ -f "$apps_dir/legacy/sub/Nested.desktop" ]] &&
  fail "tui remove deletes a launcher left nested by an older install"
pass "tui remove reaches a nested legacy launcher"

# Removing by name on a machine with no applications directory yet must stay
# quiet: this removal is called by the launcher without hiding stderr.
noise=$(HOME="$tmp_dir/empty" PATH="$tmp_dir/bin:$PATH" OMARCHY_REMOVE_NOTIFY=false \
  "$ROOT/bin/omarchy-tui-remove" "Example App" 2>&1 >/dev/null)
[[ -n $noise ]] &&
  fail "tui remove stays quiet with no applications directory" "$noise"
pass "tui remove stays quiet when there is no applications directory"