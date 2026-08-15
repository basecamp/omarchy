#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1786790068.sh"
refresh="$ROOT/bin/omarchy-refresh-applications"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
apps="$home/.local/share/applications"
icons="$apps/icons"
backup="$apps/icons.omarchy-upgrade-to-quattro.20260814150916.bak"
omarchy_path="$test_dir/omarchy"

mkdir -p "$test_dir/bin" "$omarchy_path/applications"

cat >"$test_dir/bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
[[ $1 == "update-desktop-database" ]] && exit 0
[[ $1 == "alacritty" && ${ALACRITTY_PRESENT:-} == 1 ]] && exit 0
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
export OMARCHY_PATH="$omarchy_path"

# Packaged launchers use theme icon names; leftover custom ones still point at
# the pre-Quattro PNG path the upgrade used to move away.
printf '%s\n' '[Desktop Entry]' 'Name=Basecamp' 'Icon=basecamp' >"$omarchy_path/applications/Basecamp.desktop"

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

run_refresh() {
  HOME="$home" bash "$refresh"
}

# ---------------------------------------------------------------- migration

reset_home
printf 'github-icon\n' >"$backup/GitHub.png"
printf 'chatgpt-icon\n' >"$backup/ChatGPT.png"
printf 'unrelated\n' >"$backup/windows.png"
write_desktop "$apps/GitHub.desktop" "$icons/GitHub.png"
write_desktop "$apps/ChatGPT.desktop" "$icons/ChatGPT.png"
write_desktop "$apps/Alacritty.desktop" "Alacritty"
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
write_desktop "$apps/Alacritty.desktop" "Alacritty"
ALACRITTY_PRESENT=1 run_migration

[[ -f $apps/Alacritty.desktop ]] || fail "migration keeps Alacritty.desktop when alacritty is installed"
pass "migration keeps Alacritty.desktop when alacritty is installed"

reset_home
mkdir -p "$icons"
printf 'already-there\n' >"$icons/GitHub.png"
printf 'backup-copy\n' >"$backup/GitHub.png"
write_desktop "$apps/GitHub.desktop" "$icons/GitHub.png"
ALACRITTY_PRESENT=0 run_migration

[[ $(<"$icons/GitHub.png") == already-there ]] || fail "migration does not overwrite an icon that is already in place"
[[ ! -e $CALLS || ! -s $CALLS ]] || fail "migration is a no-op when nothing needs repair" "$(cat "$CALLS")"
pass "migration is a no-op when icons are already present"

# -------------------------------------------------------- refresh-applications

reset_home
printf 'github-icon\n' >"$backup/GitHub.png"
write_desktop "$apps/GitHub.desktop" "$icons/GitHub.png"
write_desktop "$apps/Alacritty.desktop" "Alacritty"
ALACRITTY_PRESENT=0 run_refresh

[[ -f $icons/GitHub.png ]] || fail "refresh-applications restores a referenced icon from the Quattro backup"
[[ ! -e $apps/Alacritty.desktop ]] || fail "refresh-applications removes Alacritty.desktop when alacritty is missing"
[[ -f $apps/Basecamp.desktop ]] || fail "refresh-applications still installs packaged launchers"
pass "refresh-applications restores referenced icons and drops a ghost Alacritty launcher"
