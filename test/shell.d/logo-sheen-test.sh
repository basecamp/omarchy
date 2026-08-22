#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

source "$ROOT/bin/omarchy-logo-sheen"

logo="$tmp_dir/logo.txt"
write_logo() { printf '%s\n' "$@" >"$logo"; }
base=$'\e[0m\e[1m\e[32m'
pad_top=2 pad_left=2 columns=120

build() { sheen_build "$logo" "$pad_top" "$pad_left" "$base" "$columns"; }
refuses() {
  if build; then
    fail "$1"
  else
    pass "$1"
  fi
}

write_logo '████████████████████████' '████████        ████████' '████████████████████████'
build || fail "a logo of plain block art animates"
pass "a logo of plain block art animates"

mapfile -t expected <"$logo"
(( ${#SHEEN_FRAMES[@]} > ${#expected[0]} )) || fail "the glint takes more frames than the logo is wide" "${#SHEEN_FRAMES[@]}"
pass "the glint takes more frames than the logo is wide"

# Every frame is the same logo in different colours. A frame that changed a
# character, reached past the logo, or lit more than the band is wide would be
# drawing over whatever the caller put beside it, and nothing on screen would say so.
esc=$'\e'
band_width=$(( SHEEN_HALO * 2 + 1 ))
misplaced=0 rewritten=0 overrun=0 washed=0 unbased=0 widest_glint=0 first_lit=0
lit_rows=""
for index in "${!SHEEN_FRAMES[@]}"; do
  row=0
  frame_lit=0
  while IFS= read -r drawn; do
    [[ -n $drawn ]] || continue
    [[ $drawn == "$esc[$((row + pad_top + 1));$((pad_left + 1))H"* ]] || misplaced=$((misplaced + 1))

    rest=${drawn#*H}
    [[ $rest == "$base"* ]] || unbased=$((unbased + 1))
    rest=${rest#"$base"}
    head=${rest%%"$SHEEN_HALO_COLOR"*} && rest=${rest#*"$SHEEN_HALO_COLOR"}
    halo_in=${rest%%"$SHEEN_CORE_COLOR"*} && rest=${rest#*"$SHEEN_CORE_COLOR"}
    core=${rest%%"$SHEEN_HALO_COLOR"*} && rest=${rest#*"$SHEEN_HALO_COLOR"}
    halo_out=${rest%%"$base"*} && tail=${rest#*"$base"}

    lit=$(( ${#halo_in} + ${#core} + ${#halo_out} ))
    [[ $head$halo_in$core$halo_out$tail == "${expected[row]}" ]] || rewritten=$((rewritten + 1))
    (( ${#head} + lit + ${#tail} > ${#expected[row]} )) && overrun=$((overrun + 1))
    (( lit > band_width )) && washed=$((washed + 1))
    if (( lit > 0 )); then
      lit_rows+="$row "
      frame_lit=$((frame_lit + 1))
    fi
    row=$((row + 1))
  done < <(printf '%s\n' "${SHEEN_FRAMES[index]}" | sed "s/$esc\[[0-9]*;[0-9]*H/\n&/g")
  (( row == ${#expected[@]} )) || fail "a frame draws every row of the logo" "drew $row of ${#expected[@]}"
  (( frame_lit > widest_glint )) && widest_glint=$frame_lit
  (( index == 0 )) && first_lit=$frame_lit
done

(( misplaced == 0 )) || fail "every row is drawn on the cell it was given" "$misplaced misplaced"
pass "every row is drawn on the cell it was given"

(( unbased == 0 )) || fail "every row starts in the colour it was handed" "$unbased rows"
pass "every row starts in the colour it was handed"

(( rewritten == 0 )) || fail "the sheen only recolours the logo, never rewrites it" "$rewritten rows changed"
pass "the sheen only recolours the logo, never rewrites it"

(( overrun == 0 )) || fail "no frame reaches past the logo" "$overrun overruns"
pass "no frame reaches past the logo"

# A band of light leaning across the logo, not a wash over half of it.
(( washed == 0 )) || fail "the glint stays a band the whole way across" "$washed rows lit wider than $band_width"
pass "the glint stays a band the whole way across"

for row in "${!expected[@]}"; do
  [[ " $lit_rows" == *" $row "* ]] || fail "the glint crosses every row of the logo" "row $row is never lit"
done
pass "the glint crosses every row of the logo"

(( widest_glint == ${#expected[@]} )) || fail "the glint leans across the whole logo at once" "widest frame lit $widest_glint of ${#expected[@]}"
pass "the glint leans across the whole logo at once"

(( first_lit == 1 )) || fail "a glint arrives from off the logo" "the first frame lights $first_lit rows"
pass "a glint arrives from off the logo"

settled=""
for row in "${!expected[@]}"; do
  settled+="$esc[$((row + pad_top + 1));$((pad_left + 1))H$base${expected[row]}$SHEEN_HALO_COLOR$SHEEN_CORE_COLOR$SHEEN_HALO_COLOR$base"
done
[[ ${SHEEN_FRAMES[-1]} == "$settled" ]] || fail "a glint settles back to the logo it was given"
pass "a glint settles back to the logo it was given"

# A logo it cannot put back exactly as it found it is one to leave alone: nothing
# on screen would say the difference, and the row after it would move.
write_logo '$1████' '  ████'
refuses "a logo built from colour placeholders is left still"
write_logo "$(printf 'A\tB')" 'CC'
refuses "a logo with a tab someone else expands is left still"

write_logo '████████████████████████' '████████        ████████'
columns=10
refuses "a logo wider than the columns it was given is left still"
columns=120

probe=$SHEEN_PROBE
SHEEN_PROBE='ab'
refuses "a shell that is not counting characters leaves it still"
SHEEN_PROBE=$probe

: >"$logo"
refuses "an empty logo is left still"

rm -f "$logo"
missing=$(build 2>&1 >/dev/null || true)
[[ -z $missing ]] || fail "a missing logo says nothing on the terminal it would draw on" "$missing"
pass "a missing logo says nothing on the terminal it would draw on"
