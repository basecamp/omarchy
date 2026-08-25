#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"

columns() {
  awk 'NR == 1 { print length($0) }'
}

strip_sgr() {
  printf '%s' "$1" | awk -v esc=$'\033' '{ gsub(esc "\\[[0-9;]*m", ""); print }'
}

run_on_tty() {
  python3 -c '
import fcntl, os, pty, struct, subprocess, sys, termios

master, slave = pty.openpty()
fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
proc = subprocess.Popen(sys.argv[1:], stdin=slave, stdout=slave, stderr=subprocess.DEVNULL)
os.close(slave)
chunks = []
while True:
    try:
        data = os.read(master, 65536)
    except OSError:
        break
    if not data:
        break
    chunks.append(data)
proc.wait()
os.close(master)
sys.stdout.buffer.write(b"".join(chunks).replace(b"\r\n", b"\n").replace(b"\r", b""))
' "$@"
}

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

# figlet.js and figlet.c disagree about a first M: the C one trims the column of
# blanks every row of that glyph shares, the JavaScript one keeps it. asciiart.eu
# runs figlet.js, so this pins the leading blanks rather than leaving the next
# reader to "fix" them.
expected_m=$(
  cat <<'LETTER_M'
   ▄▄▄▄███▄▄▄▄
 ▄██▀▀▀███▀▀▀██▄
 ███   ███   ███
 ███   ███   ███
 ███   ███   ███
 ███   ███   ███
 ███   ███   ███
  ▀█   ███   █▀

LETTER_M
)

output=$(omarchy-ascii M)
[[ $output == "$expected_m" ]] || fail "a leading M keeps the blanks figlet.js gives it" "expected:
$expected_m
actual:
$output"
pass "a leading M keeps the blanks figlet.js gives it"

output=$(printf 'Omarchy' | omarchy-ascii)
[[ $output == "$expected" ]] || fail "text can arrive on stdin"
pass "text can arrive on stdin"

# The route is the way a user reaches this, and it dispatches on whether the
# metadata says an argument is required -- so a piped run has to be exercised
# through `omarchy` itself, not just through the binary.
output=$(printf 'Omarchy' | omarchy ascii)
[[ $output == "$expected" ]] || fail "piped text renders through the omarchy route" "got:
$output"
pass "piped text renders through the omarchy route"

# The block characters are three bytes each, so the column arithmetic has to
# count columns rather than bytes wherever the locale lands.
output=$(LC_ALL=C omarchy-ascii Omarchy)
[[ $output == "$expected" ]] || fail "a byte-only locale draws the same wordmark"
pass "a byte-only locale draws the same wordmark"

blanks=$(omarchy-ascii Omarchy | grep -c ' $' || true)
[[ $blanks == "0" ]] || fail "no line is padded with trailing blanks" "$blanks lines end in a blank"
pass "no line is padded with trailing blanks"

# The space is a glyph of five hardblank columns, so it is worth exactly five
# columns of art -- not merely more than none.
tight=$(omarchy-ascii "Hi" | columns)
spaced=$(omarchy-ascii "H i" | columns)
(( tight == 18 )) || fail "Hi is 18 columns wide" "got $tight"
(( spaced == tight + 5 )) || fail "a space between words is five columns" "expected $((tight + 5)), got $spaced"
pass "a space between words is five columns"

rows=$(omarchy-ascii Hi | wc -l)
(( rows == 9 )) || fail "a block is nine rows" "got $rows"
pass "a block is nine rows"

# An empty line is a block of its own in figlet, and dropping it would silently
# close up the gap someone put there on purpose.
rows=$(printf 'A\n\nB\n' | omarchy-ascii | wc -l)
(( rows == 27 )) || fail "an empty line still draws its block" "expected 27 rows, got $rows"
pass "an empty line still draws its block"

# awk reads escapes in a variable it is given on the command line, so text has
# to reach it as input instead: a backslash is a character the font lacks, not
# the start of an escape.
rows=$(omarchy-ascii 'A\nB' 2>/dev/null | wc -l)
(( rows == 9 )) || fail "a backslash in the text is not an escape" "expected 9 rows, got $rows"
pass "a backslash in the text is not an escape"

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

# Naming a skipped control character by writing it out would send it to the
# terminal as a control character.
warning=$(printf 'A\001B\n' | omarchy-ascii 2>&1 >/dev/null)
[[ $warning == *'\x01'* ]] || fail "a skipped control character is named by code" "got: $warning"
[[ $warning != *$'\001'* ]] || fail "a skipped control character is not written out raw"
pass "a skipped control character is named by code"

status=0
output=$(omarchy-ascii "4.0" 2>/dev/null) || status=$?
(( status == 1 )) || fail "text the font cannot draw at all fails" "exited $status"
[[ -z $output ]] || fail "text the font cannot draw at all prints nothing"
pass "text the font cannot draw at all fails"

# A mistyped option would otherwise be drawn as art, silently.
status=0
output=$(omarchy-ascii --width 40 2>&1 >/dev/null) || status=$?
(( status == 1 )) || fail "an unknown option is refused" "exited $status"
[[ $output == *"Unknown option: --width"* ]] || fail "an unknown option is named" "got: $output"
pass "an unknown option is refused"

output=$(omarchy-ascii -- Hi | columns)
(( output == 18 )) || fail "text after -- is still text" "got $output columns"
pass "text after -- is still text"

output=$(omarchy-ascii --help)
[[ $output == *"Usage: omarchy-ascii"* ]] || fail "help renders"
[[ $output == *"--color"* && $output == *"--no-color"* ]] || fail "help names the color flags" "got: $output"
[[ $output == *"terminal"* ]] || fail "help says color follows the terminal" "got: $output"
pass "help renders"

output=$(omarchy-ascii --no-color Omarchy)
[[ $output == "$expected" ]] || fail "--no-color is the raw wordmark" "expected:
$expected
actual:
$output"
pass "--no-color is the raw wordmark"

# Piped and captured runs stay uncolored so branding files and the tests above
# keep getting the same bytes. --color is how a test (or a script that wants
# the paint) asks for the theme wrap anyway.
theme_home=$(mktemp -d)
empty_home=""
trap 'rm -rf "$theme_home" "$empty_home"' EXIT
mkdir -p "$theme_home/.local/state/omarchy/current/theme"
cat >"$theme_home/.local/state/omarchy/current/theme/colors.toml" <<'TOML'
green = "#12ab34"
accent = "#ffffff"
TOML

output=$(HOME="$theme_home" omarchy-ascii --color Omarchy)
[[ $output == *$'\033[38;2;18;171;52m'* ]] || fail "--color wraps in the theme green" "got: $output"
[[ $output == *$'\033[0m'* ]] || fail "--color resets after the art" "got: $output"
[[ $output != *$'\033[38;2;255;255;255m'* ]] || fail "--color prefers green over accent"
[[ $(strip_sgr "$output") == "$expected" ]] || fail "--color keeps the same glyphs" "expected:
$expected
actual:
$(strip_sgr "$output")"
pass "--color wraps in the theme green"

output=$(HOME="$theme_home" omarchy ascii --color Omarchy)
[[ $output == *$'\033[38;2;18;171;52m'* && $(strip_sgr "$output") == "$expected" ]] ||
  fail "the omarchy route still colors when asked"
pass "the omarchy route still colors when asked"

# Accent is the fallback when a theme has no green of its own.
printf 'accent = "#aabbcc"\n' >"$theme_home/.local/state/omarchy/current/theme/colors.toml"
output=$(HOME="$theme_home" omarchy-ascii --color Omarchy)
[[ $output == *$'\033[38;2;170;187;204m'* ]] || fail "--color falls back to accent" "got: $output"
pass "--color falls back to accent"

# No theme at all: still paint, just in plain ANSI green.
empty_home=$(mktemp -d)
output=$(HOME="$empty_home" omarchy-ascii --color Omarchy)
[[ $output == *$'\033[32m'* && $output == *$'\033[0m'* ]] || fail "no theme still uses ANSI green" "got: $output"
[[ $(strip_sgr "$output") == "$expected" ]] || fail "ANSI green wrap keeps the glyphs"
pass "no theme still uses ANSI green"

# Color is only on stdout. Skipped characters still go to stderr, uncolored,
# named the same way they were before the wrap existed.
status=0
warning=$(HOME="$theme_home" omarchy-ascii --color "Omarchy 4.0" 2>&1 >/dev/null) || status=$?
(( status == 0 )) || fail "skipped characters still draw when colored" "exited $status"
[[ $warning == *"Skipped"* && $warning == *"4"* && $warning != *$'\033['* ]] ||
  fail "skipped characters stay on stderr without SGR" "got: $warning"
pass "skipped characters stay on stderr without SGR"

if command -v python3 >/dev/null; then
  tty_plain=$(HOME="$theme_home" run_on_tty omarchy-ascii --no-color Omarchy)
  tty_plain=${tty_plain%"${tty_plain##*[![:space:]]}"}
  [[ $tty_plain == "$expected" ]] || fail "--no-color stays plain on a tty" "got: $tty_plain"
  pass "--no-color stays plain on a tty"

  tty_auto=$(HOME="$theme_home" run_on_tty omarchy-ascii Omarchy)
  [[ $tty_auto == *$'\033[38;2;170;187;204m'* ]] || fail "a tty colors by default" "got: $tty_auto"
  pass "a tty colors by default"
fi
