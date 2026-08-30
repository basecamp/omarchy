#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

rule=$(OMARCHY_PATH="$ROOT" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local emitted
hl = { window_rule = function(value) emitted = value end }

require("default.hypr.helpers")
require("default.hypr.apps.omawrite")

print(table.concat({
  emitted.match.class,
  emitted.match.title,
  tostring(emitted.float),
  tostring(emitted.center),
  emitted.size[1] .. "x" .. emitted.size[2],
}, "\t"))
LUA
)

IFS=$'\t' read -r class title float center size <<<"$rule"
[[ $class == "^omawrite$" && $title == "^Save File$" ]] ||
  fail "the window rule targets only Omawrite's save dialog" "$rule"
[[ $float == "true" && $center == "true" ]] || fail "the save dialog floats and centers" "$rule"
[[ $size == "875x600" ]] || fail "the save dialog fits a scaled laptop display" "$rule"
pass "Omawrite's save dialog opens at a bounded floating size"
