#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/data/applications" "$tmp_dir/bin"

write_fake_command() {
  local name="$1"
  local prefix="$2"

  cat >"$tmp_dir/bin/$name" <<SCRIPT
#!/bin/bash
printf '%s:%s\\n' '$prefix' "\$*" >>"\$TEST_LOG"
SCRIPT
  chmod +x "$tmp_dir/bin/$name"
}

write_fake_command omarchy-webapp-remove web
write_fake_command omarchy-tui-remove tui
write_fake_command omarchy-launch-floating-terminal-with-presentation terminal

cat >"$tmp_dir/bin/pacman" <<'SCRIPT'
#!/bin/bash
if [[ $1 == "-Qqo" ]]; then
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

cat >"$tmp_dir/data/applications/native.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Native
Exec=native
DESKTOP

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$PATH"
export XDG_DATA_HOME="$tmp_dir/data"
export XDG_DATA_DIRS=

"$ROOT/bin/omarchy-remove-launcher-entry" Basecamp.desktop Basecamp
"$ROOT/bin/omarchy-remove-launcher-entry" Docker.desktop Docker
"$ROOT/bin/omarchy-remove-launcher-entry" native.desktop Native

mapfile -t lines <"$TEST_LOG"

[[ ${lines[0]} == "web:Basecamp" ]] || fail "launcher remove routes web apps by desktop name" "${lines[0]}"
pass "launcher remove routes web apps by desktop name"

[[ ${lines[1]} == "tui:Docker" ]] || fail "launcher remove routes TUIs by desktop name" "${lines[1]}"
pass "launcher remove routes TUIs by desktop name"

[[ ${lines[2]} == "terminal:echo Uninstalling Native...; sudo pacman -Rns native-pkg" ]] || fail "launcher remove opens package uninstall flow" "${lines[2]}"
pass "launcher remove opens package uninstall flow"
