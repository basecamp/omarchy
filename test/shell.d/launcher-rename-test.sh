#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/data/applications" "$tmp_dir/system/applications" "$tmp_dir/bin"

cat >"$tmp_dir/bin/update-desktop-database" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$1" >>"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/bin/update-desktop-database"

cat >"$tmp_dir/system/applications/org.example.Editor.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Editor
Name[fr]=Éditeur
Comment=Edit files
Exec=editor --open %F
Type=Application

[Desktop Action New]
Name=New document
Exec=editor --new
DESKTOP

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$PATH"
export XDG_DATA_HOME="$tmp_dir/data"
export XDG_DATA_DIRS="$tmp_dir/system"

"$ROOT/bin/omarchy-rename-launcher-entry" org.example.Editor 'Work\Editor = Primary'

renamed="$tmp_dir/data/applications/org.example.Editor.desktop"
[[ -f $renamed ]] || fail "launcher rename creates a user desktop override"
pass "launcher rename creates a user desktop override"

grep -Fx 'Name=Work\\Editor = Primary' "$renamed" >/dev/null || fail "launcher rename escapes the replacement display name"
pass "launcher rename escapes the replacement display name"

grep -Fx 'X-Omarchy-Renamed=true' "$renamed" >/dev/null || fail "launcher rename marks an override of a system entry"
pass "launcher rename marks system overrides for the uninstall path"

[[ $(grep -c '^Name=' "$renamed") == 2 ]] || fail "launcher rename changes only the main desktop-entry name" "$(grep '^Name' "$renamed")"
grep -Fx 'Name=New document' "$renamed" >/dev/null || fail "launcher rename preserves desktop action names"
! grep -q '^Name\[' "$renamed" || fail "launcher rename removes localized names that would override the chosen name"
grep -Fx 'Exec=editor --open %F' "$renamed" >/dev/null || fail "launcher rename preserves launch commands"
pass "launcher rename changes only the application display name"

grep -Fx 'Name=Editor' "$tmp_dir/system/applications/org.example.Editor.desktop" >/dev/null || fail "launcher rename leaves package-owned desktop files untouched"
pass "launcher rename leaves package-owned desktop files untouched"

[[ $(stat -c '%a' "$renamed") == 644 ]] || fail "launcher rename writes a non-executable desktop override"
[[ $(cat "$TEST_LOG") == "$tmp_dir/data/applications" ]] || fail "launcher rename refreshes the user desktop database"
pass "launcher rename installs the override safely"

cp "$renamed" "$tmp_dir/data/applications/no-name.desktop"
sed -i '/^X-Omarchy-Renamed=/d' "$tmp_dir/data/applications/no-name.desktop"
sed -i '/^Name=/d' "$tmp_dir/data/applications/no-name.desktop"
"$ROOT/bin/omarchy-rename-launcher-entry" no-name.desktop 'Added Name'
grep -Fx 'Name=Added Name' "$tmp_dir/data/applications/no-name.desktop" >/dev/null || fail "launcher rename adds a missing main name"
! grep -q '^X-Omarchy-Renamed=' "$tmp_dir/data/applications/no-name.desktop" || fail "launcher rename does not mark an in-place user entry"
pass "launcher rename adds a missing main name"

outside="$tmp_dir/outside.desktop"
printf 'keep\n' >"$outside"
ln -s "$outside" "$tmp_dir/data/applications/symlink.desktop"
if "$ROOT/bin/omarchy-rename-launcher-entry" symlink Changed 2>/dev/null; then
  fail "launcher rename rejects a symlink destination"
fi
[[ $(cat "$outside") == "keep" ]] || fail "launcher rename does not follow a destination symlink"
pass "launcher rename refuses destination symlinks"

if "$ROOT/bin/omarchy-rename-launcher-entry" '../outside' Changed 2>/dev/null; then
  fail "launcher rename rejects path traversal ids"
fi
[[ $(cat "$outside") == "keep" ]] || fail "launcher rename path validation protects files outside the applications directory"
pass "launcher rename rejects path traversal ids"

if "$ROOT/bin/omarchy-rename-launcher-entry" org.example.Editor $'Injected\nExec=bad' 2>/dev/null; then
  fail "launcher rename rejects multiline names"
fi
! grep -q '^Exec=bad$' "$renamed" || fail "launcher rename does not inject desktop-entry keys"
pass "launcher rename rejects desktop-entry injection"

menu_qml="$ROOT/shell/plugins/menu/Menu.qml"
app_library_qml="$ROOT/shell/services/AppLibrary.qml"
grep -F 'event.key === Qt.Key_R' "$menu_qml" >/dev/null || fail "menu handles the R key for rename"
grep -F '(event.modifiers & Qt.ControlModifier)' "$menu_qml" >/dev/null || fail "menu requires Ctrl for rename"
grep -F 'root.requestRenameSelected()' "$menu_qml" >/dev/null || fail "menu invokes rename for the selected application"
grep -F 'if (!row || row.kind !== "app") return false' "$menu_qml" >/dev/null || fail "menu limits rename to application rows"
grep -F 'root.appLibrary.rename(target.appId, nextName)' "$menu_qml" >/dev/null || fail "menu delegates application renames to AppLibrary"
grep -F 'Keys.onReturnPressed' "$menu_qml" >/dev/null || fail "rename field consumes Return"
grep -F 'Keys.onEnterPressed' "$menu_qml" >/dev/null || fail "rename field consumes Enter"
grep -F 'event.accepted = true' "$menu_qml" >/dev/null || fail "rename field consumes submit events"
grep -F '/bin/omarchy-rename-launcher-entry' "$app_library_qml" >/dev/null || fail "AppLibrary invokes the rename helper"
pass "menu exposes the guarded application rename flow"
