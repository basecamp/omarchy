#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command awk

source "$ROOT/default/bash/fns/screensaver"

assert_font_size() {
  local scale="$1" expected="$2"
  local actual
  actual=$(omarchy_screensaver_font_size "$scale")
  [[ $actual == "$expected" ]] ||
    fail "screensaver font size for scale $scale" "expected $expected, got $actual"
  pass "screensaver font size for scale $scale is $expected"
}

# The wordmark fills ~1178 physical px at font 18. Shrinking the font by the
# monitor scale keeps that physical size — and with it, the column budget —
# the same on every display, which a fixed 18pt font did not: at scale 2 a
# 1080p panel offered only 66 of the 81 columns the art needs.
assert_font_size 1 18
assert_font_size 2 9
assert_font_size 1.25 14
assert_font_size 1.5 12
assert_font_size 3 6
assert_font_size 4 6

# Sub-unity scales (fractional UI zoom) are capped at the shipped default.
assert_font_size 0.5 18

# The launcher hands each terminal the computed size; no fixed 18 survives in
# the launch paths.
launcher="$ROOT/bin/omarchy-launch-screensaver"
grep -F 'omarchy_screensaver_font_size' "$launcher" >/dev/null ||
  fail "screensaver launcher sizes its terminal fonts from the monitor scale"
for literal in '--font-size=18' 'font_size=18' 'size = 18.0'; do
  if grep -Fq -- "$literal" "$launcher"; then
    fail "screensaver launcher does not hardcode $literal"
  fi
done
pass "screensaver launcher sizes its terminal fonts from the monitor scale"