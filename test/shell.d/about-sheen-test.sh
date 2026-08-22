#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# The launcher ends by taking over the process, so source it short of that line
# and the sheen can be built here, without a terminal to draw it on.
about="$ROOT/bin/omarchy-launch-about"
grep -q '^presize_window$' "$about" || fail "About launcher can be sourced short of its launch"
sed '/^presize_window$/,$d' "$about" >"$tmp_dir/about.bash"

export HOME="$tmp_dir/home"
mkdir -p "$HOME/.config/omarchy/branding"
logo="$HOME/.config/omarchy/branding/about.txt"
write_logo() { printf '%s\n' "$@" >"$logo"; }
write_logo '████████████████████████' '████████        ████████' '████████████████████████'

source "$tmp_dir/about.bash"

# Stand in for the terminal, and for the fastfetch run that measures the layout.
esc=$'\e'
rows_by_cols="45 140"
layout_rows=20
logo_color="$esc[1m$esc[32m"
stty() { printf '%s\n' "$rows_by_cols"; }
measure_layout() {
  LAYOUT_ROWS=$layout_rows
  LOGO_COLOR=$logo_color
}

# fastfetch resolves the home directory from the passwd database rather than
# $HOME, so it would answer for the real one. Stand in for it with the search
# order it prints, pointed at this test's directories.
config_paths=(
  "$HOME/.config/fastfetch/"
  "$HOME/fastfetch/"
  "$OMARCHY_FASTFETCH_DIR/ (*)"
  "$HOME/searched-later/fastfetch/"
)
fastfetch() {
  [[ ${1:-} == "--list-config-paths" ]] || return 1
  printf '%s\n' "${config_paths[@]}"
}

# The sheen repaints the cells fastfetch drew the logo on, so its idea of the
# padding has to be the config's. Read them from the config rather than from the
# launcher, or a drift between the two would agree with itself and go unseen.
config_top=$(jq -r '.logo.padding.top' "$ROOT/etc/fastfetch/config.jsonc")
config_left=$(jq -r '.logo.padding.left' "$ROOT/etc/fastfetch/config.jsonc")
config_right=$(jq -r '.logo.padding.right' "$ROOT/etc/fastfetch/config.jsonc")

[[ $LOGO_PAD_TOP == "$config_top" && $LOGO_PAD_LEFT == "$config_left" && $LOGO_PAD_RIGHT == "$config_right" ]] ||
  fail "the launcher's padding is the fastfetch config's" "config: $config_top/$config_left/$config_right, launcher: $LOGO_PAD_TOP/$LOGO_PAD_LEFT/$LOGO_PAD_RIGHT"
pass "the launcher's padding is the fastfetch config's"

build_sheen || fail "a logo that fits its window animates"
pass "a logo that fits its window animates"

# fastfetch draws the logo in its own colour. A glint that handed the cells back
# in a plain reset would repaint the logo a different colour on its first pass,
# and leave it that way.
[[ $SHEEN_BASE == "$esc[0m$logo_color" ]] || fail "an unlit cell is fastfetch's own colour" "$(printf '%q' "$SHEEN_BASE")"
pass "an unlit cell is fastfetch's own colour"

mapfile -t expected <"$logo"
(( ${#SHEEN_FRAMES[@]} > ${#expected[0]} )) || fail "the glint takes more frames than the logo is wide" "${#SHEEN_FRAMES[@]}"
pass "the glint takes more frames than the logo is wide"

# Every frame is the same logo in different colours. A frame that changed a
# character, reached past the logo, or lit more than the band is wide would be
# drawing over fastfetch's own output, and nothing on screen would say so.
band_width=$(( SHEEN_HALO * 2 + 1 ))
misplaced=0 rewritten=0 overrun=0 washed=0 unbased=0 widest_glint=0
lit_rows=""
for frame in "${SHEEN_FRAMES[@]}"; do
  row=0
  frame_lit=0
  while IFS= read -r drawn; do
    [[ -n $drawn ]] || continue
    [[ $drawn == "$esc[$((row + config_top + 1));$((config_left + 1))H"* ]] || misplaced=$((misplaced + 1))

    rest=${drawn#*H}
    [[ $rest == "$SHEEN_BASE"* ]] || unbased=$((unbased + 1))
    rest=${rest#"$SHEEN_BASE"}
    head=${rest%%"$SHEEN_HALO_COLOR"*} && rest=${rest#*"$SHEEN_HALO_COLOR"}
    halo_in=${rest%%"$SHEEN_CORE_COLOR"*} && rest=${rest#*"$SHEEN_CORE_COLOR"}
    core=${rest%%"$SHEEN_HALO_COLOR"*} && rest=${rest#*"$SHEEN_HALO_COLOR"}
    halo_out=${rest%%"$SHEEN_BASE"*} && tail=${rest#*"$SHEEN_BASE"}

    lit=$(( ${#halo_in} + ${#core} + ${#halo_out} ))
    [[ $head$halo_in$core$halo_out$tail == "${expected[row]}" ]] || rewritten=$((rewritten + 1))
    (( ${#head} + lit + ${#tail} > ${#expected[row]} )) && overrun=$((overrun + 1))
    (( lit > band_width )) && washed=$((washed + 1))
    if (( lit > 0 )); then
      lit_rows+="$row "
      frame_lit=$((frame_lit + 1))
    fi
    row=$((row + 1))
  done < <(printf '%s\n' "$frame" | sed "s/$esc\[[0-9]*;[0-9]*H/\n&/g")
  (( row == ${#expected[@]} )) || fail "a frame draws every row of the logo" "drew $row of ${#expected[@]}"
  (( frame_lit > widest_glint )) && widest_glint=$frame_lit
done

(( misplaced == 0 )) || fail "every row is drawn on the cell fastfetch put it on" "$misplaced misplaced"
pass "every row is drawn on the cell fastfetch put it on"

(( unbased == 0 )) || fail "every row starts in the colour fastfetch drew it in" "$unbased rows"
pass "every row starts in the colour fastfetch drew it in"

(( rewritten == 0 )) || fail "the sheen only recolours the logo, never rewrites it" "$rewritten rows changed"
pass "the sheen only recolours the logo, never rewrites it"

(( overrun == 0 )) || fail "no frame reaches past the logo into the module column" "$overrun overruns"
pass "no frame reaches past the logo into the module column"

# A band of light leaning across the logo, not a wash over half of it.
(( washed == 0 )) || fail "the glint stays a band the whole way across" "$washed rows lit wider than $band_width"
pass "the glint stays a band the whole way across"

for row in "${!expected[@]}"; do
  [[ " $lit_rows" == *" $row "* ]] || fail "the glint crosses every row of the logo" "row $row is never lit"
done
pass "the glint crosses every row of the logo"

(( widest_glint == ${#expected[@]} )) || fail "the glint leans across the whole logo at once" "widest frame lit $widest_glint of ${#expected[@]} rows"
pass "the glint leans across the whole logo at once"

# The glint arrives from off the logo rather than appearing on it: on the first
# frame only the corner it enters by is lit.
first_lit=0
while IFS= read -r drawn; do
  [[ -n $drawn ]] || continue
  rest=${drawn#*H}
  rest=${rest#"$SHEEN_BASE"}
  rest=${rest#*"$SHEEN_HALO_COLOR"}
  halo_in=${rest%%"$SHEEN_CORE_COLOR"*} && rest=${rest#*"$SHEEN_CORE_COLOR"}
  core=${rest%%"$SHEEN_HALO_COLOR"*} && rest=${rest#*"$SHEEN_HALO_COLOR"}
  halo_out=${rest%%"$SHEEN_BASE"*}
  (( ${#halo_in} + ${#core} + ${#halo_out} > 0 )) && first_lit=$((first_lit + 1))
done < <(printf '%s\n' "${SHEEN_FRAMES[0]}" | sed "s/$esc\[[0-9]*;[0-9]*H/\n&/g")
(( first_lit == 1 )) || fail "a glint arrives from off the logo" "the first frame lights $first_lit rows"
pass "a glint arrives from off the logo"

# The band leaves the logo before the last frame, so what a glint settles back to
# is the logo whole, in fastfetch's colour — the same screen it started from.
last=${SHEEN_FRAMES[-1]}
settled=""
for row in "${!expected[@]}"; do
  settled+="$esc[$((row + config_top + 1));$((config_left + 1))H$SHEEN_BASE${expected[row]}$SHEEN_HALO_COLOR$SHEEN_CORE_COLOR$SHEEN_HALO_COLOR$SHEEN_BASE"
done
[[ $last == "$settled" ]] || fail "a glint settles back to the logo fastfetch drew" "$(printf '%q' "$last")"
pass "a glint settles back to the logo fastfetch drew"

# Anything that moves the logo off those cells, or means the text on screen is
# not the text in the file, has to leave the logo still rather than guess.
refuses() {
  if build_sheen; then
    fail "$1"
  else
    pass "$1"
  fi
}

# fastfetch reads the first config it finds across several directories, and any
# of them ahead of Omarchy's own can put the logo somewhere else entirely.
for directory in .config/fastfetch fastfetch; do
  mkdir -p "$HOME/$directory"
  touch "$HOME/$directory/config.jsonc"
  refuses "a fastfetch config in ~/$directory leaves the logo still"
  rm -r "${HOME:?}/$directory"
done

# One fastfetch would never read, because Omarchy's own comes first, is not a
# reason to stop: the logo on screen is still the one this draws.
mkdir -p "$HOME/searched-later/fastfetch"
touch "$HOME/searched-later/fastfetch/config.jsonc"
build_sheen || fail "a config fastfetch searches after Omarchy's own still animates"
pass "a config fastfetch searches after Omarchy's own still animates"
rm -r "${HOME:?}/searched-later"

write_logo '$1████' '  ████'
refuses "a logo built from fastfetch colour placeholders leaves it still"
write_logo "$(printf '\t████')" '  ████'
refuses "a logo with a tab fastfetch expands itself leaves it still"
write_logo '████████████████████████' '████████        ████████' '████████████████████████'

rows_by_cols="$layout_rows 140"
refuses "a window with no room past the layout's last line leaves it still"
rows_by_cols="45 6"
refuses "a window too narrow for the logo leaves it still"
rows_by_cols="45 140"

measure_layout() { return 1; }
refuses "a layout fastfetch cannot be measured from leaves it still"
measure_layout() {
  LAYOUT_ROWS=$layout_rows
  LOGO_COLOR=$logo_color
}

probe=$SHEEN_PROBE
SHEEN_PROBE='ab'
refuses "a shell that is not counting characters leaves it still"
SHEEN_PROBE=$probe

: >"$logo"
refuses "an empty logo leaves it still"

rm -f "$logo"
missing=$(build_sheen 2>&1 >/dev/null || true)
[[ -z $missing ]] || fail "a missing logo says nothing on the terminal it would draw on" "$missing"
pass "a missing logo says nothing on the terminal it would draw on"
