#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

# Load the rules the way Hyprland does, under a stubbed hl, and print what
# reaches the compositor. Grepping the file's text instead would pass on a rule
# file that is entirely commented out.
localsend_rules() {
  OMARCHY_PATH="$ROOT" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local emitted = {}
hl = { window_rule = function(rule) table.insert(emitted, rule) end }

require("default.hypr.helpers")
require("default.hypr.apps.localsend")

for _, rule in ipairs(emitted) do
  print(string.format(
    "%s\t%s\t%s\t%s",
    rule.match.class,
    tostring(rule.float),
    tostring(rule.center),
    rule.size and (rule.size[1] .. "x" .. rule.size[2]) or "none"
  ))
end
LUA
}

# Hyprland matches a class against the whole string, so anchors in the rule are
# optional and this supplies them either way. Bash's ERE stands in for RE2:
# they agree on alternation and escaped dots, which is all these patterns use.
claims() {
  local class=$1 pattern=$2

  pattern=${pattern#'^'}
  pattern=${pattern%'$'}

  [[ $class =~ ^($pattern)$ ]]
}

readarray -t rules < <(localsend_rules)
(( ${#rules[@]} == 2 )) || fail "LocalSend emits its float and size rules" "got ${#rules[@]} rules"

IFS=$'\t' read -r float_class float center _ <<<"${rules[0]}"
IFS=$'\t' read -r size_class _ _ size <<<"${rules[1]}"

[[ $float == "true" && $center == "true" ]] || fail "LocalSend floats and centers" "float=$float center=$center"
pass "LocalSend floats and centers"

[[ $size == "1100x700" ]] || fail "LocalSend gets the intended size" "size=$size"
pass "LocalSend gets the intended size"

for class in "org.localsend.localsend_app" localsend; do
  claims "$class" "$float_class" || fail "LocalSend's app ids float and center" "$class misses $float_class"
  claims "$class" "$size_class" || fail "LocalSend's app ids are sized" "$class misses $size_class"
done
pass "LocalSend's current and legacy app ids float, center and size"

claims Share "$float_class" || fail "the Share picker still floats" "Share misses $float_class"
if claims Share "$size_class"; then
  fail "the Share picker keeps its own size" "Share matches $size_class"
fi
pass "the Share picker floats without LocalSend's size"

# An unescaped dot is a wildcard, and a rule carrying one would claim windows
# that only look like LocalSend.
if claims orgXlocalsendXlocalsend_app "$float_class"; then
  fail "LocalSend's rule escapes its dots" "an unescaped dot matches $float_class"
fi
pass "LocalSend's rule escapes its dots"
