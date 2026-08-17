#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/data/applications" "$tmp_dir/system/applications" "$tmp_dir/bin"

write_fake_command() {
  local name="$1"
  local prefix="$2"

  cat >"$tmp_dir/bin/$name" <<SCRIPT
#!/bin/bash
printf '%s:%s:%s\\n' '$prefix' "\${OMARCHY_REMOVE_NOTIFY:-}" "\$*" >>"\$TEST_LOG"
SCRIPT
  chmod +x "$tmp_dir/bin/$name"
}

write_fake_command omarchy-webapp-remove web
write_fake_command omarchy-tui-remove tui
write_fake_command omarchy-launch-floating-terminal-with-presentation terminal

cat >"$tmp_dir/bin/omarchy-notification-send" <<'SCRIPT'
#!/bin/bash
printf 'notify::%s\n' "$*" >>"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/bin/omarchy-notification-send"

cat >"$tmp_dir/bin/update-desktop-database" <<'SCRIPT'
#!/bin/bash
:
SCRIPT
chmod +x "$tmp_dir/bin/update-desktop-database"

cat >"$tmp_dir/bin/pacman" <<'SCRIPT'
#!/bin/bash
if [[ $1 == "-Qqo" && $2 == */native.desktop ]]; then
  printf 'native-pkg\n'
fi
SCRIPT
chmod +x "$tmp_dir/bin/pacman"

cat >"$tmp_dir/data/applications/Basecamp.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Basecamp
Exec=omarchy-launch-webapp https://example.com
DESKTOP

cat >"$tmp_dir/data/applications/Docker.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Docker
Exec=xdg-terminal-exec --app-id=TUI.tile -e lazydocker
DESKTOP

cat >"$tmp_dir/system/applications/native.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Native
Exec=native
DESKTOP

cat >"$tmp_dir/data/applications/aliens.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Aliens
Exec=retroarch -L /usr/lib/libretro/fbneo_libretro.so /home/example/Games/roms/fbneo/aliens.zip
DESKTOP

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$PATH"
export XDG_DATA_HOME="$tmp_dir/data"
export XDG_DATA_DIRS="$tmp_dir/system"

"$ROOT/bin/omarchy-remove-launcher-entry" Basecamp.desktop Basecamp
"$ROOT/bin/omarchy-remove-launcher-entry" Docker.desktop Docker
"$ROOT/bin/omarchy-remove-launcher-entry" native.desktop Native
"$ROOT/bin/omarchy-remove-launcher-entry" aliens.desktop Aliens

mapfile -t lines <"$TEST_LOG"

[[ ${lines[0]} == "web:false:Basecamp" ]] || fail "launcher remove routes web apps by desktop name" "${lines[0]}"
pass "launcher remove routes web apps by desktop name"

[[ ${lines[1]} == "tui:false:Docker" ]] || fail "launcher remove routes TUIs by desktop name" "${lines[1]}"
pass "launcher remove routes TUIs by desktop name"

[[ ${lines[2]} == "terminal::echo Uninstalling Native...; sudo pacman -Rns native-pkg" ]] || fail "launcher remove opens package uninstall flow" "${lines[2]}"
pass "launcher remove opens package uninstall flow"

[[ ! -e $tmp_dir/data/applications/aliens.desktop ]] || fail "launcher remove deletes user-owned desktop files"
pass "launcher remove deletes user-owned desktop files"

(( ${#lines[@]} == 3 )) || fail "launcher remove does not notify for user-owned desktop files" "$(printf '%s\n' "${lines[@]}")"
pass "launcher remove does not notify for user-owned desktop files"

# Test omarchy-webapp-remove directly with multiple apps
rm -f "$tmp_dir/bin/omarchy-webapp-remove"
mkdir -p "$tmp_dir/.local/share/icons/hicolor/256x256/apps" "$tmp_dir/.local/share/applications"
cat >"$tmp_dir/.local/share/applications/App1.desktop" <<'DESKTOP'
[Desktop Entry]
Name=App1
Exec=omarchy-launch-webapp https://app1.com
DESKTOP
touch "$tmp_dir/.local/share/icons/hicolor/256x256/apps/app1.png"

cat >"$tmp_dir/.local/share/applications/App2.desktop" <<'DESKTOP'
[Desktop Entry]
Name=App2
Exec=omarchy-launch-webapp https://app2.com
DESKTOP
touch "$tmp_dir/.local/share/icons/hicolor/256x256/apps/app2.png"

cat >"$tmp_dir/bin/omarchy-menu-select" <<'SCRIPT'
#!/bin/bash
[[ " $* " == *" --multi "* ]] || exit 1
printf '%s\n' "$FAKE_SELECTION"
SCRIPT
chmod +x "$tmp_dir/bin/omarchy-menu-select"

FAKE_SELECTION=$'App1\nApp2' HOME="$tmp_dir" OMARCHY_REMOVE_NOTIFY=false "$ROOT/bin/omarchy-webapp-remove"

[[ ! -e "$tmp_dir/.local/share/applications/App1.desktop" ]] || fail "omarchy-webapp-remove removes first pinned app"
[[ ! -e "$tmp_dir/.local/share/applications/App2.desktop" ]] || fail "omarchy-webapp-remove removes second pinned app"
[[ ! -e "$tmp_dir/.local/share/icons/hicolor/256x256/apps/app1.png" ]] || fail "omarchy-webapp-remove removes first app icon"
[[ ! -e "$tmp_dir/.local/share/icons/hicolor/256x256/apps/app2.png" ]] || fail "omarchy-webapp-remove removes second app icon"
pass "omarchy-webapp-remove removes multiple pinned web apps"

cat >"$tmp_dir/.local/share/applications/Tui1.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Tui1
Exec=xdg-terminal-exec --app-id=TUI.tile -e lazygit
DESKTOP
touch "$tmp_dir/.local/share/icons/hicolor/256x256/apps/tui1.png"

cat >"$tmp_dir/.local/share/applications/Tui2.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Tui2
Exec=xdg-terminal-exec --app-id=TUI.tile -e btop
DESKTOP
touch "$tmp_dir/.local/share/icons/hicolor/256x256/apps/tui2.png"

FAKE_SELECTION=$'Tui1\nTui2' HOME="$tmp_dir" OMARCHY_REMOVE_NOTIFY=false "$ROOT/bin/omarchy-tui-remove"

[[ ! -e "$tmp_dir/.local/share/applications/Tui1.desktop" ]] || fail "omarchy-tui-remove removes first pinned TUI"
[[ ! -e "$tmp_dir/.local/share/applications/Tui2.desktop" ]] || fail "omarchy-tui-remove removes second pinned TUI"
[[ ! -e "$tmp_dir/.local/share/icons/hicolor/256x256/apps/tui1.png" ]] || fail "omarchy-tui-remove removes first TUI icon"
[[ ! -e "$tmp_dir/.local/share/icons/hicolor/256x256/apps/tui2.png" ]] || fail "omarchy-tui-remove removes second TUI icon"
pass "omarchy-tui-remove removes multiple pinned TUIs"

mkdir -p "$tmp_dir/.config/omarchy/themes/Theme One" "$tmp_dir/.config/omarchy/themes/Theme Two"
FAKE_SELECTION=$'Theme One\nTheme Two' HOME="$tmp_dir" "$ROOT/bin/omarchy-theme-remove"

[[ ! -d "$tmp_dir/.config/omarchy/themes/Theme One" ]] || fail "omarchy-theme-remove removes first pinned theme"
[[ ! -d "$tmp_dir/.config/omarchy/themes/Theme Two" ]] || fail "omarchy-theme-remove removes second pinned theme"
pass "omarchy-theme-remove removes multiple pinned themes"

if HOME="$tmp_dir" "$ROOT/bin/omarchy-theme-remove" definitely-missing >/dev/null 2>&1; then
  fail "omarchy-theme-remove reports missing themes"
fi
pass "omarchy-theme-remove reports missing themes"
