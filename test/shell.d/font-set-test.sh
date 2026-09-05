#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
stub_bin="$test_tmp/bin"
mkdir -p "$test_home/.config/"{foot,alacritty,kitty,ghostty,fontconfig} "$stub_bin"

# fc-list must report the family as installed; other side effects are stubbed.
cat >"$stub_bin/fc-list" <<'SH'
#!/bin/bash
printf 'CaskaydiaMono Nerd Font:style=Regular\nJetBrainsMono Nerd Font:style=Regular\n'
SH

cat >"$stub_bin/omarchy-restart-shell" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-hook" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/pgrep" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$stub_bin/pkill" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$stub_bin"/*

printf '%s\n' \
  '[main]' \
  'font=JetBrainsMono Nerd Font:size=12' \
  'pad=14x14' >"$test_home/.config/foot/foot.ini"

printf '%s\n' \
  '[font.normal]' \
  'family = "JetBrainsMono Nerd Font"' \
  'size = 12' >"$test_home/.config/alacritty/alacritty.toml"

printf '%s\n' \
  'font_family JetBrainsMono Nerd Font' \
  'font_size 12.0' >"$test_home/.config/kitty/kitty.conf"

printf '%s\n' \
  'font-family = "JetBrainsMono Nerd Font"' \
  'font-size = 12' >"$test_home/.config/ghostty/config"

run_font_set() {
  HOME="$test_home" PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-font-set" "$@"
}

run_font_set "CaskaydiaMono Nerd Font"

foot_font=$(grep -E '^font=' "$test_home/.config/foot/foot.ini")
[[ $foot_font == "font=CaskaydiaMono Nerd Font:size=12" ]] ||
  fail "font-set preserves foot point size while changing family" "$foot_font"
pass "font-set preserves foot point size while changing family"

grep -F 'family = "CaskaydiaMono Nerd Font"' "$test_home/.config/alacritty/alacritty.toml" >/dev/null ||
  fail "font-set updates alacritty family"
grep -E '^size = 12$' "$test_home/.config/alacritty/alacritty.toml" >/dev/null ||
  fail "font-set leaves alacritty size alone"
pass "font-set updates alacritty family without touching size"

grep -E '^font_family CaskaydiaMono Nerd Font$' "$test_home/.config/kitty/kitty.conf" >/dev/null ||
  fail "font-set updates kitty family"
grep -E '^font_size 12.0$' "$test_home/.config/kitty/kitty.conf" >/dev/null ||
  fail "font-set leaves kitty size alone"
pass "font-set updates kitty family without touching size"

grep -F 'font-family = "CaskaydiaMono Nerd Font"' "$test_home/.config/ghostty/config" >/dev/null ||
  fail "font-set updates ghostty family"
grep -E '^font-size = 12$' "$test_home/.config/ghostty/config" >/dev/null ||
  fail "font-set leaves ghostty size alone"
pass "font-set updates ghostty family without touching size"

# Foot line without an explicit size must still take the new family.
printf '%s\n' 'font=Old Family' >"$test_home/.config/foot/foot.ini"
run_font_set "CaskaydiaMono Nerd Font"
foot_font=$(grep -E '^font=' "$test_home/.config/foot/foot.ini")
[[ $foot_font == "font=CaskaydiaMono Nerd Font" ]] ||
  fail "font-set rewrites a size-less foot font line" "$foot_font"
pass "font-set rewrites a size-less foot font line"

# Fractional sizes from display-text-size must survive too.
printf '%s\n' 'font=JetBrainsMono Nerd Font:size=11.5' >"$test_home/.config/foot/foot.ini"
run_font_set "CaskaydiaMono Nerd Font"
foot_font=$(grep -E '^font=' "$test_home/.config/foot/foot.ini")
[[ $foot_font == "font=CaskaydiaMono Nerd Font:size=11.5" ]] ||
  fail "font-set preserves fractional foot sizes" "$foot_font"
pass "font-set preserves fractional foot sizes"
