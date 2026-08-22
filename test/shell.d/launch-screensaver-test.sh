#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
home_dir="$tmp_dir/home"
screensaver_path="$home_dir/.config/omarchy/branding/screensaver.txt"
mkdir -p "$stub_bin" "${screensaver_path%/*}" "$tmp_dir/runtime/hypr/test-instance"

for ((line = 0; line < 20; line++)); do
  printf '%120s\n' "" | tr ' ' X
done >"$screensaver_path"

cat >"$stub_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash

exit 1
SH

cat >"$stub_bin/pgrep" <<'SH'
#!/bin/bash

exit 1
SH

cat >"$stub_bin/omarchy-toggle-enabled" <<'SH'
#!/bin/bash

exit 1
SH

cat >"$stub_bin/omarchy-hyprland-monitor-focused" <<'SH'
#!/bin/bash

printf '%s\n' "Large"
SH

cat >"$stub_bin/xdg-terminal-exec" <<'SH'
#!/bin/bash

printf '%s\n' "$OMARCHY_TEST_TERMINAL"
SH

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "monitors" && $2 == "-j" ]]; then
  cat <<'JSON'
[
  {"name":"Large","width":1920,"height":1080,"scale":1},
  {"name":"Small","width":941,"height":509,"scale":1},
  {"name":"Portrait","width":1200,"height":1920,"scale":1,"transform":1}
]
JSON
else
  printf '%s\n' "$*" >>"$OMARCHY_TEST_HYPRCTL_LOG"
fi
SH

cat >"$stub_bin/socat" <<'SH'
#!/bin/bash

printf '%s\n' \
  "openwindow>>1,0,org.omarchy.screensaver,title" \
  "openwindow>>2,0,org.omarchy.screensaver,title" \
  "openwindow>>3,0,org.omarchy.screensaver,title"
SH

chmod +x "$stub_bin"/*

export HOME="$home_dir"
export PATH="$stub_bin:$PATH"
export OMARCHY_PATH="$ROOT"
export XDG_RUNTIME_DIR="$tmp_dir/runtime"
export HYPRLAND_INSTANCE_SIGNATURE="test-instance"
export OMARCHY_TEST_HYPRCTL_LOG="$tmp_dir/hyprctl.log"

assert_terminal_sizes() {
  local terminal="$1"
  local large_pattern="$2"
  local small_pattern="$3"
  local portrait_pattern="$4"

  export OMARCHY_TEST_TERMINAL="$terminal"
  : >"$OMARCHY_TEST_HYPRCTL_LOG"
  "$ROOT/bin/omarchy-launch-screensaver" force

  (( $(grep -c 'hl.dsp.exec_cmd' "$OMARCHY_TEST_HYPRCTL_LOG") == 3 )) \
    || fail "Screensaver launches once per monitor for $terminal"
  grep -Fq -- "$large_pattern" "$OMARCHY_TEST_HYPRCTL_LOG" \
    || fail "Screensaver keeps the normal font size on the large monitor for $terminal" "$(<"$OMARCHY_TEST_HYPRCTL_LOG")"
  grep -Fq -- "$small_pattern" "$OMARCHY_TEST_HYPRCTL_LOG" \
    || fail "Screensaver scales oversized text on the small monitor for $terminal" "$(<"$OMARCHY_TEST_HYPRCTL_LOG")"
  grep -Fq -- "$portrait_pattern" "$OMARCHY_TEST_HYPRCTL_LOG" \
    || fail "Screensaver swaps dimensions for rotated monitors on $terminal" "$(<"$OMARCHY_TEST_HYPRCTL_LOG")"
}

assert_terminal_sizes "Alacritty.desktop" "font.size=18" "font.size=9" "font.size=18"
assert_terminal_sizes "ghostty.desktop" "--font-size=18" "--font-size=9" "--font-size=18"
assert_terminal_sizes "foot.desktop" "--font=JetBrainsMono\\ Nerd\\ Font:size=18" "--font=JetBrainsMono\\ Nerd\\ Font:size=9" "--font=JetBrainsMono\\ Nerd\\ Font:size=18"
assert_terminal_sizes "kitty.desktop" "font_size=18" "font_size=9" "font_size=18"
pass "Screensaver scales generated ASCII art for every supported terminal"
