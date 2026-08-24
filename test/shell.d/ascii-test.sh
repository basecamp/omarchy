#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"

# The wordmark FIGlet itself draws for this font, so a change to the embedded
# font or to the kerning shows up here rather than in someone's terminal.
expected=$(
  cat <<'WORDMARK'
 ▄██████▄    ▄▄▄▄███▄▄▄▄      ▄████████    ▄████████  ▄████████    ▄█    █▄    ▄██   ▄
███    ███ ▄██▀▀▀███▀▀▀██▄   ███    ███   ███    ███ ███    ███   ███    ███   ███   ██▄
███    ███ ███   ███   ███   ███    ███   ███    ███ ███    █▀    ███    ███   ███▄▄▄███
███    ███ ███   ███   ███   ███    ███  ▄███▄▄▄▄██▀ ███         ▄███▄▄▄▄███▄▄ ▀▀▀▀▀▀███
███    ███ ███   ███   ███ ▀███████████ ▀▀███▀▀▀▀▀   ███        ▀▀███▀▀▀▀███▀  ▄██   ███
███    ███ ███   ███   ███   ███    ███ ▀███████████ ███    █▄    ███    ███   ███   ███
███    ███ ███   ███   ███   ███    ███   ███    ███ ███    ███   ███    ███   ███   ███
 ▀██████▀   ▀█   ███   █▀    ███    █▀    ███    ███ ████████▀    ███    █▀     ▀█████▀
                                          ███    ███
WORDMARK
)

output=$(omarchy-ascii Omarchy)
[[ $output == "$expected" ]] || fail "the wordmark matches the reference rendering" "expected:
$expected
actual:
$output"
pass "the wordmark matches the reference rendering"

output=$(printf 'Omarchy' | omarchy-ascii)
[[ $output == "$expected" ]] || fail "text can arrive on stdin"
pass "text can arrive on stdin"

# The block characters are three bytes each, so the column arithmetic has to
# count columns rather than bytes wherever the locale lands.
output=$(LC_ALL=C omarchy-ascii Omarchy)
[[ $output == "$expected" ]] || fail "a byte-only locale draws the same wordmark"
pass "a byte-only locale draws the same wordmark"

output=$(omarchy-ascii Omarchy | grep -c ' $' || true)
[[ $output == "0" ]] || fail "no line is padded with trailing blanks" "$output lines end in a blank"
pass "no line is padded with trailing blanks"

spaced=$(omarchy-ascii "H i" | head -1 | wc -c)
tight=$(omarchy-ascii "Hi" | head -1 | wc -c)
(( spaced > tight )) || fail "a space between words keeps its width" "spaced $spaced, tight $tight"
pass "a space between words keeps its width"

lines=$(printf 'Hi\nHi\n' | omarchy-ascii | wc -l)
single=$(omarchy-ascii Hi | wc -l)
(( lines == single * 2 )) || fail "each input line draws its own block" "expected $((single * 2)) lines, got $lines"
pass "each input line draws its own block"

# Delta Corps Priest 1 carries letters and spaces only. Dropping the rest in
# silence would leave a version number looking like a bug in the renderer.
status=0
warning=$(omarchy-ascii "Omarchy 4.0" 2>&1 >/dev/null) || status=$?
(( status == 0 )) || fail "text with unusable characters still draws" "exited $status"
[[ $warning == *"Skipped"* && $warning == *"4"* && $warning == *"."* && $warning == *"0"* ]] ||
  fail "skipped characters are named on stderr" "got: $warning"
pass "skipped characters are named on stderr"

output=$(omarchy-ascii "Omarchy 4.0" 2>/dev/null)
[[ $output == "$expected" ]] || fail "the drawable characters still render"
pass "the drawable characters still render"

status=0
output=$(omarchy-ascii "4.0" 2>/dev/null) || status=$?
(( status == 1 )) || fail "text the font cannot draw at all fails" "exited $status"
[[ -z $output ]] || fail "text the font cannot draw at all prints nothing"
pass "text the font cannot draw at all fails"

output=$(omarchy-ascii --help)
[[ $output == *"Usage: omarchy-ascii"* ]] || fail "help renders"
pass "help renders"
