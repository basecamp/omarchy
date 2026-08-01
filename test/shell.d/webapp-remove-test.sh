#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/home/.local/share/applications" "$tmp_dir/bin"

cat >"$tmp_dir/bin/hyprctl" <<'SCRIPT'
#!/bin/bash
printf 'hyprctl:%s\n' "$*" >>"$TEST_LOG"
SCRIPT

cat >"$tmp_dir/bin/update-desktop-database" <<'SCRIPT'
#!/bin/bash
:
SCRIPT

cat >"$tmp_dir/bin/omarchy-notification-send" <<'SCRIPT'
#!/bin/bash
:
SCRIPT

chmod +x "$tmp_dir/bin"/*

cat >"$tmp_dir/home/.local/share/applications/YouTube.desktop" <<'DESKTOP'
[Desktop Entry]
Name=YouTube
Exec=omarchy-launch-webapp https://youtube.com/
DESKTOP

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$PATH"

HOME="$tmp_dir/home" "$ROOT/bin/omarchy-webapp-remove" YouTube

[[ ! -e $tmp_dir/home/.local/share/applications/YouTube.desktop ]] || fail "web app removal deletes the launcher entry"
pass "web app removal deletes the launcher entry"

grep -Fxq 'hyprctl:reload' "$TEST_LOG" || fail "web app removal reloads Hyprland so its binding goes away" "$(cat "$TEST_LOG")"
pass "web app removal reloads Hyprland so its binding goes away"
