#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1788173342.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
apps="$home/.local/share/applications"
icons="$apps/icons"
backup="$apps/icons.omarchy-upgrade-to-quattro.20260814150916.bak"

mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
[[ $1 == "update-desktop-database" ]] && exit 0
exit 1
STUB

cat >"$test_dir/bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
[[ $1 == "alacritty" && ${ALACRITTY_PRESENT:-} == 1 ]] && exit 1
exit 0
STUB

cat >"$test_dir/bin/update-desktop-database" <<'STUB'
#!/bin/bash
printf 'update-desktop-database %s\n' "$*" >>"$CALLS"
STUB

chmod +x "$test_dir/bin/"*

export CALLS="$test_dir/calls"
export PATH="$test_dir/bin:$PATH"

write_desktop() {
  local path="$1" icon="$2"
  printf '%s\n' '[Desktop Entry]' 'Name=Test' "Icon=$icon" >"$path"
}

reset_home() {
  rm -rf "$home"
  mkdir -p "$apps" "$backup"
  : >"$CALLS"
}

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

reset_home
printf 'github-icon\n' >"$backup/GitHub.png"
printf 'chatgpt-icon\n' >"$backup/ChatGPT.png"
printf 'unrelated\n' >"$backup/windows.png"
write_desktop "$apps/GitHub.desktop" "$icons/GitHub.png"
write_desktop "$apps/ChatGPT.desktop" "$icons/ChatGPT.png"
cp "$ROOT/default/alacritty/Alacritty.desktop" "$apps/Alacritty.desktop"
ALACRITTY_PRESENT=0 run_migration

[[ -f $icons/GitHub.png ]] || fail "migration restores a referenced GitHub icon from the Quattro backup"
[[ -f $icons/ChatGPT.png ]] || fail "migration restores a referenced ChatGPT icon from the Quattro backup"
[[ ! -e $icons/windows.png ]] || fail "migration leaves unreferenced backup icons parked"
[[ ! -e $apps/Alacritty.desktop ]] || fail "migration removes Alacritty.desktop when alacritty is missing"
grep -q 'update-desktop-database' "$CALLS" || fail "migration refreshes the desktop database after a repair"
pass "migration restores referenced icons and drops a ghost Alacritty launcher"

reset_home
printf 'github-icon\n' >"$backup/GitHub.png"
write_desktop "$apps/GitHub.desktop" "$icons/GitHub.png"
cp "$ROOT/default/alacritty/Alacritty.desktop" "$apps/Alacritty.desktop"
ALACRITTY_PRESENT=1 run_migration

[[ -f $apps/Alacritty.desktop ]] || fail "migration keeps Alacritty.desktop when alacritty is installed"
pass "migration keeps Alacritty.desktop when alacritty is installed"

reset_home
write_desktop "$apps/Alacritty.desktop" "Alacritty"
ALACRITTY_PRESENT=0 run_migration

[[ -f $apps/Alacritty.desktop ]] || fail "migration keeps a custom Alacritty.desktop when alacritty is missing"
pass "migration keeps a custom Alacritty.desktop when alacritty is missing"

reset_home
mkdir -p "$icons"
printf 'already-there\n' >"$icons/GitHub.png"
printf 'backup-copy\n' >"$backup/GitHub.png"
write_desktop "$apps/GitHub.desktop" "$icons/GitHub.png"
ALACRITTY_PRESENT=0 run_migration

[[ $(<"$icons/GitHub.png") == already-there ]] || fail "migration does not overwrite an icon that is already in place"
[[ ! -e $CALLS || ! -s $CALLS ]] || fail "migration is a no-op when nothing needs repair" "$(cat "$CALLS")"
pass "migration is a no-op when icons are already present"

reset_home
printf 'github-icon\n' >"$backup/GitHub.png"
write_desktop "$apps/GitHub.desktop" "$icons/../GitHub.png"
ALACRITTY_PRESENT=0 run_migration

[[ ! -e $apps/GitHub.png ]] || fail "migration does not restore through a parent path in Icon="
[[ ! -e $icons/GitHub.png ]] || fail "migration does not restore a non-exact Icon= path"
pass "migration ignores Icon= paths that leave the icons directory"

reset_home
mkdir -p "$icons"
ln -s "$icons/missing.png" "$icons/GitHub.png"
printf 'github-icon\n' >"$backup/GitHub.png"
write_desktop "$apps/GitHub.desktop" "$icons/GitHub.png"
printf 'chatgpt-icon\n' >"$backup/ChatGPT.png"
write_desktop "$apps/ChatGPT.desktop" "$icons/ChatGPT.png"
ALACRITTY_PRESENT=0 run_migration

[[ -L $icons/GitHub.png ]] || fail "migration leaves a dangling icon symlink in place"
[[ ! -e $icons/GitHub.png ]] || fail "migration does not replace a dangling icon symlink"
[[ -f $icons/ChatGPT.png ]] || fail "migration still restores later launchers after a dangling icon symlink"
pass "migration skips a dangling icon symlink without aborting"

# omarchy-migrate runs migrations with bash -euo pipefail, and the Quattro
# upgrade now aborts outright when one does not complete, so every hazard below
# costs a half-upgraded machine rather than one unrepaired icon.

reset_home
printf 'github-icon\n' >"$backup/GitHub.png"
write_desktop "$apps/ChatGPT.desktop" "$icons/ChatGPT.png"
chmod 000 "$apps/ChatGPT.desktop"
write_desktop "$apps/GitHub.desktop" "$icons/GitHub.png"
# Mode 000 does not stop root, and a pass that proves nothing is worse than none.
if [[ -r $apps/ChatGPT.desktop ]]; then
  echo "skip - the unreadable .desktop case needs an unprivileged user"
else
  ALACRITTY_PRESENT=0 run_migration
  [[ -f $icons/GitHub.png ]] || fail "migration still restores launchers past an unreadable .desktop"
  pass "migration survives an unreadable .desktop"
fi
chmod 644 "$apps/ChatGPT.desktop"

reset_home
printf 'github-icon\n' >"$backup/GitHub.png"
ln -s "$home/nowhere" "$icons"
write_desktop "$apps/GitHub.desktop" "$icons/GitHub.png"
ALACRITTY_PRESENT=0 run_migration

[[ -L $icons ]] || fail "migration leaves a dangling icons directory symlink in place"
pass "migration survives a dangling icons directory symlink"

reset_home
older="$apps/icons.omarchy-upgrade-to-quattro.20260101000000.bak"
mkdir -p "$older"
printf 'older-icon\n' >"$older/GitHub.png"
printf 'newer-icon\n' >"$backup/GitHub.png"
write_desktop "$apps/GitHub.desktop" "$icons/GitHub.png"
ALACRITTY_PRESENT=0 run_migration

[[ $(<"$icons/GitHub.png") == newer-icon ]] || fail "migration restores from the newest upgrade backup" "$(<"$icons/GitHub.png")"
pass "migration restores from the newest upgrade backup"
