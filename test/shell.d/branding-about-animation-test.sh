#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

animation="$ROOT/bin/omarchy-branding-about-animation"
source "$animation"

logo="$tmp_dir/logo.txt"
write_logo() { printf '%s\n' "$@" >"$logo"; }
base=$'\e[0m\e[1m\e[32m'
top=3 left=3 columns=120

build() { sheen_build "$logo" "$top" "$left" "$base" "$columns"; }
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
band_width=$(( SHEEN_HALF * 2 + 1 ))
misplaced=0 rewritten=0 overrun=0 washed=0 unbased=0 widest_glint=0 first_lit=0
lit_rows=""
for index in "${!SHEEN_FRAMES[@]}"; do
  row=0
  frame_lit=0
  while IFS= read -r drawn; do
    [[ -n $drawn ]] || continue
    [[ $drawn == "$esc[$((top + row));${left}H"* ]] || misplaced=$((misplaced + 1))

    rest=${drawn#*H}
    [[ $rest == "$base"* ]] || unbased=$((unbased + 1))
    rest=${rest#"$base"}
    head=${rest%%"$SHEEN_BAND"*} && rest=${rest#*"$SHEEN_BAND"}
    lit=${rest%%"$base"*} && tail=${rest#*"$base"}

    [[ $head$lit$tail == "${expected[row]}" ]] || rewritten=$((rewritten + 1))
    (( ${#head} + ${#lit} + ${#tail} > ${#expected[row]} )) && overrun=$((overrun + 1))
    (( ${#lit} > band_width )) && washed=$((washed + 1))
    if (( ${#lit} > 0 )); then
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
  settled+="$esc[$((top + row));${left}H$base${expected[row]}$SHEEN_BAND$base"
done
[[ ${SHEEN_FRAMES[-1]} == "$settled" ]] || fail "a glint settles back to the logo it was given"
pass "a glint settles back to the logo it was given"

# A terminal that renders bold text in bright colours — foot's bold-text-in-bright
# does exactly this — maps a bold regular colour to its bright counterpart, so a
# band using one of those vanishes into a logo drawn in the matching regular
# colour, and nobody sees the animation at all.
[[ ! $SHEEN_BAND =~ \[9[0-6]m ]] || fail "the band avoids the colours a bold logo can brighten into" "$(printf '%q' "$SHEEN_BAND")"
pass "the band avoids the colours a bold logo can brighten into"

# One character has to be one cell, or putting a row back moves what follows it.
# Everything that breaks that is refused by the one check, so everything that
# breaks it is tested against the one check.
write_logo '$1████' '  ████'
refuses "a logo built from colour placeholders is left still"
write_logo "$(printf 'A\tB')" 'CC'
refuses "a logo with a tab someone else expands is left still"
write_logo "$(printf 'A\033[31mB')" 'CCCCC'
refuses "a logo carrying an escape is left still"
write_logo 'AAA中文BBB' 'CCCCCCCCCC'
refuses "a logo with double-width glyphs is left still"
write_logo "$(printf 'AAAe\xcc\x81BBB')" 'CCCCCCCC'
refuses "a logo with a combining mark is left still"
write_logo "$(printf 'AA\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9BB')" 'CCCCCCC'
refuses "a logo with a joined emoji is left still"

# The same check answers for a shell that is counting bytes rather than
# characters, which is the only thing that would make a block logo unsafe here.
write_logo '████████' '████████'
byte_counting=$(LC_ALL=C bash -c 'source "$1"; sheen_build "$2" 3 3 "" 120 && echo animated || echo still' _ "$animation" "$logo")
[[ $byte_counting == "still" ]] || fail "a shell counting bytes leaves a block logo still" "$byte_counting"
pass "a shell counting bytes leaves a block logo still"

ascii_counting=$(LC_ALL=C bash -c 'printf "%s\n" AAAA BBBB > "$2"; source "$1"; sheen_build "$2" 3 3 "" 120 && echo animated || echo still' _ "$animation" "$tmp_dir/ascii.txt")
[[ $ascii_counting == "animated" ]] || fail "a shell counting bytes still animates plain ASCII" "$ascii_counting"
pass "a shell counting bytes still animates plain ASCII"

write_logo '████████████████████████' '████████        ████████'
columns=10
refuses "a logo wider than the columns it was given is left still"
columns=120

: >"$logo"
refuses "an empty logo is left still"

rm -f "$logo"
missing=$(build 2>&1 >/dev/null || true)
[[ -z $missing ]] || fail "a missing logo says nothing on the terminal it would draw on" "$missing"
pass "a missing logo says nothing on the terminal it would draw on"
