#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

command="$ROOT/bin/omarchy-clipboard-transform"

assert_print() {
  local mode="$1"
  local input="$2"
  local expected="$3"
  local description="$4"
  local actual

  actual=$(printf '%s' "$input" | "$command" --print "$mode")
  [[ $actual == "$expected" ]] || fail "$description" "expected:
$expected
actual:
$actual"
  pass "$description"
}

assert_print upper "hello world" "HELLO WORLD" "upper converts letters to uppercase"
assert_print lower "HELLO WORLD" "hello world" "lower converts letters to lowercase"
assert_print title "hello world" "Hello World" "title capitalizes each word"
assert_print title "FOO bar Baz" "Foo Bar Baz" "title lowercases the rest of each word"
assert_print title "• hello world
  • indented bullet
1. first numbered
\"quoted text\"
hello-world hyphenated" "• Hello World
  • Indented Bullet
1. First Numbered
\"Quoted Text\"
Hello-World Hyphenated" "title preserves bullets, indent, quotes, and hyphens"
assert_print sentence "Hello World Foo Bar. Second Sentence Here." "Hello world foo bar. Second sentence here." "sentence lowercases then capitalizes sentence starts"
assert_print swapcase "Hello World" "hELLO wORLD" "swapcase inverts letter case"

if printf '' | "$command" --print title; then
  pass "empty input is a no-op"
else
  fail "empty input is a no-op"
fi

if printf '%s' "%MCEPASTEBIN%" | "$command" --print title; then
  output=$(printf '%s' "%MCEPASTEBIN%" | "$command" --print title)
  [[ -z $output ]] || fail "clipboard-manager placeholder is ignored" "got: $output"
  pass "clipboard-manager placeholder is ignored"
else
  fail "clipboard-manager placeholder is ignored"
fi

if printf '%s' "hello" | "$command" --print nope >/dev/null 2>&1; then
  fail "unknown mode exits non-zero"
else
  pass "unknown mode exits non-zero"
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/wl-paste" <<'SH'
#!/bin/bash
if [[ ${1:-} == "-p" ]]; then
  printf '%s' "$WL_PASTE_PRIMARY"
fi
SH

cat >"$TMPDIR/bin/wl-copy" <<'SH'
#!/bin/bash
args="$*"
target="$WL_COPY_OUT"
if [[ $args == "--type text/plain --sensitive --foreground" ]]; then
  target="$WL_COPY_TRANSFORM_OUT"
fi

printf '%s\n' "$args" >"$target.args"
cat >"$target"
SH

cat >"$TMPDIR/bin/wtype" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$WTYPE_OUT"
SH

cat >"$TMPDIR/bin/sleep" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$TMPDIR/bin/wl-paste" "$TMPDIR/bin/wl-copy" "$TMPDIR/bin/wtype" "$TMPDIR/bin/sleep"

WL_PASTE_PRIMARY="hello world" WL_COPY_OUT="$TMPDIR/copy" WL_COPY_TRANSFORM_OUT="$TMPDIR/transform" WTYPE_OUT="$TMPDIR/wtype" PATH="$TMPDIR/bin:$PATH" \
  "$command" title

[[ $(<"$TMPDIR/transform") == "Hello World" ]] || fail "transform helper copies transformed text transiently"
pass "transform helper copies transformed text transiently"

[[ $(<"$TMPDIR/transform.args") == "--type text/plain --sensitive --foreground" ]] || fail "transform helper serves sensitive transient clipboard in foreground"
pass "transform helper serves transient clipboard in foreground"

[[ $(<"$TMPDIR/wtype") == "-M shift -k Insert -m shift" ]] || fail "transform helper pastes with shift insert"
pass "transform helper pastes with shift insert"

WL_PASTE_PRIMARY="%MCEPASTEBIN%" WL_COPY_OUT="$TMPDIR/copy-empty" WL_COPY_TRANSFORM_OUT="$TMPDIR/transform-empty" WTYPE_OUT="$TMPDIR/wtype-empty" PATH="$TMPDIR/bin:$PATH" \
  "$command" title

[[ ! -e $TMPDIR/wtype-empty ]] || fail "placeholder selection does not paste"
pass "placeholder selection does not paste"
