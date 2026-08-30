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
# The wrapper takes argv now. Keep the joined line the other assertions count on,
# and record the words themselves so the uninstall can be replayed as argv.
cat >"$tmp_dir/bin/omarchy-launch-floating-terminal-with-presentation" <<'SCRIPT'
#!/bin/bash
printf '%s:%s:%s\n' 'terminal' "${OMARCHY_REMOVE_NOTIFY:-}" "$*" >>"$TEST_LOG"
printf '%s\n' "$@" >"$TEST_ARGV"
SCRIPT
chmod +x "$tmp_dir/bin/omarchy-launch-floating-terminal-with-presentation"

# The replayed uninstall reaches for sudo; run what it asks for rather than the
# real thing.
cat >"$tmp_dir/bin/sudo" <<'SCRIPT'
#!/bin/bash
exec "$@"
SCRIPT
chmod +x "$tmp_dir/bin/sudo"

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
# -Qqo is the ownership lookup every removal makes; only the removal itself is
# worth logging, so the lookup stays out of $TEST_LOG and off the line count.
if [[ $1 == "-Qqo" ]]; then
  [[ $2 == */native.desktop ]] && printf 'native-pkg\n'
  exit 0
fi

printf 'pacman:%s\n' "$*" >>"$TEST_LOG"
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
export TEST_ARGV="$tmp_dir/argv"
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

mapfile -t uninstall_argv <"$TEST_ARGV"

# The name and the package travel as their own words, so a display name holding
# a space or a quote can no longer reshape the command that removes it.
[[ ${uninstall_argv[0]} == "bash" && ${uninstall_argv[1]} == "-c" ]] ||
  fail "launcher remove hands the wrapper a command and its arguments" "$(printf '%s\n' "${uninstall_argv[@]}")"
[[ ${uninstall_argv[4]} == "Native" && ${uninstall_argv[5]} == "native-pkg" ]] ||
  fail "launcher remove passes the display name and the package as separate words" "$(printf '%s\n' "${uninstall_argv[@]}")"

: >"$TEST_LOG"
"${uninstall_argv[@]}" >/dev/null
grep -Fxq 'pacman:-Rns native-pkg' "$TEST_LOG" ||
  fail "launcher remove opens package uninstall flow" "$(cat "$TEST_LOG")"
pass "launcher remove opens package uninstall flow"

[[ ! -e $tmp_dir/data/applications/aliens.desktop ]] || fail "launcher remove deletes user-owned desktop files"
pass "launcher remove deletes user-owned desktop files"

(( ${#lines[@]} == 3 )) || fail "launcher remove does not notify for user-owned desktop files" "$(printf '%s\n' "${lines[@]}")"
pass "launcher remove does not notify for user-owned desktop files"
