#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STUBS="$TMPDIR/stubs"
mkdir -p "$STUBS"
export PATH="$STUBS:$ROOT/bin:$PATH"

MODEL="$ROOT/shell/plugins/screensaver-text/ScreensaverTextModel.js"

stub() {
  local name="$1"
  shift
  printf '#!/bin/bash\n%s\n' "$*" >"$STUBS/$name"
  chmod +x "$STUBS/$name"
}

monitors() {
  stub hyprctl "cat <<'JSON'
$1
JSON"
}

stub omarchy-launch-screensaver 'exit 0'
stub omarchy-notification-send 'printf "%s\n" "$*" >>"$TMPDIR/notifications"'
stub omarchy-shell 'printf "%s\n" "$*" >>"$TMPDIR/summons"'
sed -i "s|\$TMPDIR|$TMPDIR|" "$STUBS/omarchy-notification-send" "$STUBS/omarchy-shell"

branding="$TMPDIR/.config/omarchy/branding"

run_node_test <<'JS'
const model = requireFromRoot('shell/plugins/screensaver-text/ScreensaverTextModel.js')

assertEqual(model.columnsFor('Omarchy'), 88, 'the wordmark measures 88 columns')
assertEqual(model.columnsFor(''), 0, 'empty text measures nothing')
assertEqual(model.columnsFor('omarchy'), model.columnsFor('OMARCHY'), 'case does not change the width')

// Trailing blanks come off the art, so a space at the end is free until
// something follows it.
assertEqual(model.columnsFor('Hi '), model.columnsFor('Hi'), 'a trailing space costs nothing')
assert(model.columnsFor('H i') > model.columnsFor('Hi'), 'a space between letters costs something')

assert(model.drawable('a'), 'a letter is drawable')
assert(model.drawable(' '), 'a space is drawable')
assert(!model.drawable('4'), 'a digit is not drawable')
assert(!model.drawable('.'), 'a full stop is not drawable')
assert(!model.drawable('ab'), 'only single characters are drawable')

// U+017F upper cases to S and U+0131 to I, so a check on the upper case alone
// would let through two characters the renderer cannot draw.
assert(!model.drawable('ſ'), 'a long s is not drawable though it upper cases to S')
assert(!model.drawable('ı'), 'a dotless i is not drawable though it upper cases to I')
assertEqual(model.extended('A', 'ſ', 200), 'A', 'a long s is refused rather than typed')

assertEqual(model.extended('Omarch', 'y', 200), 'Omarchy', 'a character that fits is typed')
assertEqual(model.extended('Omarch', 'y', 80), 'Omarch', 'a character that would overflow is dropped')
assertEqual(model.extended('Omarch', '4', 200), 'Omarch', 'a character the font cannot draw is dropped')
assertEqual(model.extended('', 'M', 10), '', 'even the first character has to fit')

// A space nobody can see is a space that silently eats the next letter's room.
assertEqual(model.extended('', ' ', 200), '', 'the text cannot open with a space')
assertEqual(model.extended('A ', ' ', 200), 'A ', 'a second space in a row is refused')
assertEqual(model.extended('A', ' ', 200), 'A ', 'a space between words is allowed')
assertEqual(model.extended('Omarchy', ' ', 88), 'Omarchy', 'a space with no room for a letter after it is refused')
assertEqual(model.extended('Omarchy', ' ', 98), 'Omarchy ', 'a space with room for a letter after it is allowed')

assert(model.fits('Omarchy', 88), 'art exactly as wide as the screen fits')
assert(!model.fits('Omarchy', 87), 'a column too wide does not fit')
JS

# The table is a measurement of a font that lives in another file, so measure the
# renderer and check every entry against it: each letter alone for its width in
# first position, and each between two others for what it adds after one.
probes=()
for c in {A..Z} {a..z}; do probes+=("$c"); done
for c in {A..Z} {a..z}; do probes+=("A${c}A"); done
probes+=("A A" "A  A" " A" "Omarchy" "Hi" "H i" "Set From Text" "Wavy" "jelly" "MMMM" "iiii")

predicted=$(node -e '
  const model = require(process.argv[1])
  console.log(process.argv.slice(2).map(w => model.columnsFor(w)).join("\n"))
' "$MODEL" "${probes[@]}")

actual=$(printf '%s\n' "${probes[@]}" |
  omarchy-ascii |
  LC_ALL=C.UTF-8 awk '{ w = length($0); if (w > max) max = w } NR % 9 == 0 { print max; max = 0 }')

[[ $predicted == "$actual" ]] || fail "the model measures what omarchy-ascii draws" "predicted:
$predicted
actual:
$actual"
pass "the model measures what omarchy-ascii draws"

# 1280 wide at scale 1 is 91 columns of JetBrains Mono at size 18, measured in a
# real screensaver terminal. The narrowest monitor is the one the art must fit.
monitors '[{"width":1280,"height":800,"scale":1.0,"transform":0},{"width":3840,"height":2160,"scale":1.0,"transform":0}]'
HOME="$TMPDIR" omarchy-branding-screensaver words
summon=$(<"$TMPDIR/summons")
[[ $summon == *"omarchy.screensaver-text"* ]] || fail "the menu entry summons the text panel" "got: $summon"
[[ $summon == *'"columns":91'* ]] || fail "the panel is told the narrowest monitor's columns" "got: $summon"
pass "the panel is told the narrowest monitor's columns"

# A terminal cannot draw a fractional cell, so it rounds one: 14.4 at scale 1.5
# is a 22 pixel column, which is 87 of them across 1920 rather than 88.
rm -f "$TMPDIR/summons"
monitors '[{"width":1920,"height":1080,"scale":1.5,"transform":0}]'
HOME="$TMPDIR" omarchy-branding-screensaver words
[[ $(<"$TMPDIR/summons") == *'"columns":87'* ]] || fail "a fractional scale rounds to whole pixel columns" "got: $(<"$TMPDIR/summons")"
pass "a fractional scale rounds to whole pixel columns"

rm -f "$TMPDIR/summons"
monitors '[{"width":3840,"height":2160,"scale":2.0,"transform":0}]'
HOME="$TMPDIR" omarchy-branding-screensaver words
[[ $(<"$TMPDIR/summons") == *'"columns":132'* ]] || fail "a doubled scale counts its own columns" "got: $(<"$TMPDIR/summons")"
pass "a doubled scale counts its own columns"

# A monitor on its side is as wide as it is tall.
rm -f "$TMPDIR/summons"
monitors '[{"width":1920,"height":1080,"scale":1.0,"transform":1}]'
HOME="$TMPDIR" omarchy-branding-screensaver words
[[ $(<"$TMPDIR/summons") == *'"columns":77'* ]] || fail "a rotated monitor measures across its height" "got: $(<"$TMPDIR/summons")"
pass "a rotated monitor measures across its height"

rm -f "$TMPDIR/summons"
stub hyprctl 'exit 1'
HOME="$TMPDIR" omarchy-branding-screensaver words
[[ $(<"$TMPDIR/summons") == *'"columns":80'* ]] || fail "no compositor falls back to the width the image path targets" "got: $(<"$TMPDIR/summons")"
pass "no compositor falls back to the width the image path targets"

monitors '[{"width":1920,"height":1080,"scale":1.0,"transform":0}]'
HOME="$TMPDIR" omarchy-branding-screensaver words Omarchy
[[ -f $branding/screensaver.txt ]] || fail "typed words are written to the screensaver branding"
width=$(LC_ALL=C.UTF-8 wc -L <"$branding/screensaver.txt")
(( width == 88 )) || fail "the art is the width the model predicted" "got $width columns"
grep -q '█' "$branding/screensaver.txt" || fail "the branding file holds drawn art"
pass "typed words are drawn into the screensaver branding"

# The last row of an A is blank, and a variable would have eaten it: the art has
# to reach the file exactly as the renderer drew it, or ttfx centres it wrong.
HOME="$TMPDIR" omarchy-branding-screensaver words A
rows=$(wc -l <"$branding/screensaver.txt")
direct=$(omarchy-ascii A | wc -l)
(( rows == direct )) || fail "the art keeps every row the renderer drew" "file has $rows rows, renderer draws $direct"
pass "the art keeps every row the renderer drew"

# A screen the art does not fit is the whole reason the input is capped, so the
# command that the panel calls has to refuse it too.
before=$(cat "$branding/screensaver.txt")
status=0
HOME="$TMPDIR" omarchy-branding-screensaver words "Something far too long to fit" || status=$?
(( status == 1 )) || fail "text wider than the screen is refused" "exited $status"
[[ $(cat "$branding/screensaver.txt") == "$before" ]] || fail "a refused text leaves the branding alone"
[[ $(<"$TMPDIR/notifications") == *"Text too long"* ]] || fail "a refused text says why" "got: $(<"$TMPDIR/notifications")"
pass "text wider than the screen is refused"

rm -f "$TMPDIR/notifications"
status=0
HOME="$TMPDIR" omarchy-branding-screensaver words "4.0" 2>/dev/null || status=$?
(( status == 1 )) || fail "text the font cannot draw is refused" "exited $status"
[[ $(<"$TMPDIR/notifications") == *"Nothing to draw"* ]] || fail "undrawable text says why" "got: $(<"$TMPDIR/notifications")"
pass "text the font cannot draw is refused"

# The panel will not let a digit be typed, but the command is reachable without
# it, and dropping half the text in silence would look like a renderer bug.
warning=$(HOME="$TMPDIR" omarchy-branding-screensaver words "R2D2" 2>&1 >/dev/null)
[[ $warning == *"Skipped"* && $warning == *"2"* ]] || fail "characters the font skipped are named" "got: $warning"
pass "characters the font skipped are named"

status=0
HOME="$TMPDIR" omarchy-branding-screensaver bogus 2>/dev/null || status=$?
(( status == 1 )) || fail "an unknown subcommand still fails" "exited $status"
pass "an unknown subcommand still fails"
