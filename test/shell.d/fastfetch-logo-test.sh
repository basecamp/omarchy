#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

config="$ROOT/etc/fastfetch/config.jsonc"
helper="$ROOT/bin/omarchy-fastfetch-logo"
compact="$ROOT/etc/fastfetch/logo.txt"
small="$ROOT/etc/fastfetch/logo-small.txt"
full="$ROOT/logo.txt"

jq empty "$config"
pass "fastfetch config is valid JSON"

type=$(jq -r '.logo.type' "$config")
source_cmd=$(jq -r '.logo.source' "$config")
[[ $type == "command-raw" ]] || fail "fastfetch sizes the logo; file logos cannot" "$type"
pass "fastfetch sizes the logo; file logos cannot"
[[ $source_cmd == "omarchy-fastfetch-logo" ]] || fail "fastfetch prints the Omarchy wordmark helper" "$source_cmd"
pass "fastfetch prints the Omarchy wordmark helper"
[[ $source_cmd != *about.txt* ]] || fail "fastfetch is not the 26-row About icon" "$source_cmd"
pass "fastfetch is not the 26-row About icon"
[[ $(jq -r '.logo.color["1"]' "$config") == "green" ]] || fail "the wordmark stays green"
pass "the wordmark stays green"

config_top=$(jq -r '.logo.padding.top' "$config")
config_left=$(jq -r '.logo.padding.left' "$config")
config_right=$(jq -r '.logo.padding.right' "$config")
[[ $config_top == "2" && $config_left == "2" && $config_right == "6" ]] ||
  fail "padding is still what About measures" "$config_top/$config_left/$config_right"
pass "padding is still what About measures"

box=$(jq -r '[.modules[] | select(type == "object" and .type == "custom") | .format][0]' "$config")
box_plain=$(printf '%s' "$box" | sed 's/\x1b\[[0-9;]*m//g')
box_width=${#box_plain}
[[ $box_width == "54" ]] || fail "the module box is 54 columns so the picker can leave room for it" "$box_width"
pass "the module box is 54 columns so the picker can leave room for it"

grep -q '^PAD_LEFT=2$' "$helper" && grep -q '^PAD_RIGHT=6$' "$helper" && grep -q '^PAD_TOP=2$' "$helper" ||
  fail "the picker's padding is the config's"
pass "the picker's padding is the config's"
grep -q '^MODULE_COLUMNS=54$' "$helper" || fail "the picker subtracts the module box"
pass "the picker subtracts the module box"

[[ -x $helper ]] || fail "the wordmark helper is executable"
pass "the wordmark helper is executable"
[[ -f $compact && -f $small && -f $full ]] || fail "full, compact, and small wordmarks are shipped"
pass "full, compact, and small wordmarks are shipped"

line_width() {
  local file=$1 line max=0
  while IFS= read -r line || [[ -n $line ]]; do
    if (( ${#line} > max )); then
      max=${#line}
    fi
  done <"$file"
  printf '%s' "$max"
}

full_w=$(line_width "$full")
compact_w=$(line_width "$compact")
small_w=$(line_width "$small")
full_h=$(wc -l <"$full")
compact_h=$(wc -l <"$compact")
small_h=$(wc -l <"$small")
icon_h=$(wc -l <"$ROOT/icon.txt")

(( compact_w < full_w && compact_h <= full_h )) || fail "the compact wordmark is smaller than the full one" "$compact_w×$compact_h vs $full_w×$full_h"
pass "the compact wordmark is smaller than the full one"
(( small_w < compact_w && small_h < icon_h )) || fail "the small mark is smaller than the compact wordmark and the About icon" "$small_w×$small_h vs compact $compact_w icon $icon_h"
pass "the small mark is smaller than the compact wordmark and the About icon"

# 80-column terminals are the ones the huge About icon broke: padding + 54-column
# modules leave this much for the logo, and the small mark has to fit in it.
room=$(( 80 - config_left - config_right - 54 ))
(( small_w <= room )) || fail "the small mark fits beside the modules in 80 columns" "logo $small_w, room $room"
pass "the small mark fits beside the modules in 80 columns"

export OMARCHY_PATH="$ROOT"
export PATH="$ROOT/bin:$PATH"
export NO_COLOR=1

run_logo() {
  COLUMNS=$1 LINES=$2 omarchy-fastfetch-logo
}

wide=$(run_logo 160 40)
[[ $wide == *"▄███████████▄"* ]] || fail "a wide terminal gets the full wordmark" "$wide"
pass "a wide terminal gets the full wordmark"

medium=$(run_logo 120 40)
[[ $medium == *"▄█████▄"* && $medium != *"▄███████████▄"* ]] || fail "a medium terminal gets the compact wordmark" "$medium"
pass "a medium terminal gets the compact wordmark"

tight=$(run_logo 80 24)
[[ $tight == *"██████████████"* && $tight != *"▄█████▄"* ]] || fail "an 80-column terminal gets the compact O" "$tight"
pass "an 80-column terminal gets the compact O"

# Smaller than the small mark still prints it rather than falling through to a
# builtin arch logo — the thing the issue must not become.
narrow=$(run_logo 40 12)
[[ -n $narrow && $narrow == "$tight" ]] || fail "a terminal too small for any mark still prints the compact O" "$narrow"
pass "a terminal too small for any mark still prints the compact O"

[[ $wide == *$'\e'* || $medium == *$'\e'* || $tight == *$'\e'* ]] && fail "NO_COLOR leaves the wordmark uncoloured"
pass "NO_COLOR leaves the wordmark uncoloured"

unset NO_COLOR
coloured=$(COLUMNS=80 LINES=24 omarchy-fastfetch-logo)
[[ $coloured == *$'\e[1m\e[32m'* ]] || fail "the wordmark is bold green" "$(printf '%q' "$coloured")"
pass "the wordmark is bold green"

# About keeps the branding file as a file logo so the sheen can find those cells.
grep -q 'about_fastfetch' "$ROOT/bin/omarchy-launch-about" || fail "About still draws through a branding-file fastfetch"
pass "About still draws through a branding-file fastfetch"
[[ $(jq -r '.logo.source' "$config") != "~/.config/omarchy/branding/about.txt" ]] || fail "the packaged config is not About's file logo"
pass "the packaged config is not About's file logo"
