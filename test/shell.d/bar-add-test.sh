#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"

require_command jq

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
config="$home/.config/omarchy/shell.json"
widget="omarchy.keyboard-layout"

write_config() {
  rm -rf "$home"
  mkdir -p "$home/.config/omarchy"
  cat >"$config"
}

add() {
  HOME="$home" omarchy-bar add "$@"
}

ids() {
  jq -c --arg section "$1" '[.bar.layout[$section][]? | if type == "object" then .id else . end]' "$config"
}

plain_bar() {
  write_config <<'JSON'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [{ "id": "omarchy.menu" }],
      "center": [{ "id": "omarchy.clock" }, { "id": "omarchy.weather" }],
      "right": [{ "id": "omarchy.tray" }]
    }
  },
  "plugins": []
}
JSON
}

plain_bar
add "$widget" --after omarchy.clock >/dev/null
[[ $(ids center) == '["omarchy.clock","omarchy.keyboard-layout","omarchy.weather"]' ]] ||
  fail "add places a widget after the named one" "$(ids center)"
pass "add places a widget after the named one"

# Running it again must not add a second copy or move the first.
add "$widget" --section right >/dev/null
[[ $(ids center) == '["omarchy.clock","omarchy.keyboard-layout","omarchy.weather"]' && $(ids right) == '["omarchy.tray"]' ]] ||
  fail "add leaves a widget already on the bar alone" "center: $(ids center) right: $(ids right)"
pass "add leaves a widget already on the bar alone"

plain_bar
add "$widget" --before omarchy.weather >/dev/null
[[ $(ids center) == '["omarchy.clock","omarchy.keyboard-layout","omarchy.weather"]' ]] ||
  fail "add places a widget before the named one" "$(ids center)"
pass "add places a widget before the named one"

# The anchor is looked for in the target section, so one that isn't there just
# leaves the widget at the end rather than failing the command.
plain_bar
add "$widget" --after omarchy.nonexistent >/dev/null
[[ $(ids center) == '["omarchy.clock","omarchy.weather","omarchy.keyboard-layout"]' ]] ||
  fail "add falls back to the end of the section" "$(ids center)"
pass "add falls back to the end of the section"

plain_bar
add "$widget" right >/dev/null
[[ $(ids right) == '["omarchy.tray","omarchy.keyboard-layout"]' ]] ||
  fail "add takes a positional section" "$(ids right)"
pass "add takes a positional section"

plain_bar
add "$widget" --section right --index 0 >/dev/null
[[ $(ids right) == '["omarchy.keyboard-layout","omarchy.tray"]' ]] ||
  fail "add honors an explicit index" "$(ids right)"
pass "add honors an explicit index"

# A widget the user moved elsewhere counts as present wherever it sits.
write_config <<'JSON'
{
  "version": 1,
  "bar": { "layout": { "left": [{ "id": "omarchy.keyboard-layout" }], "center": [{ "id": "omarchy.clock" }] } },
  "plugins": []
}
JSON
add "$widget" --after omarchy.clock >/dev/null
[[ $(ids left) == '["omarchy.keyboard-layout"]' && $(ids center) == '["omarchy.clock"]' ]] ||
  fail "add respects a widget the user moved" "left: $(ids left) center: $(ids center)"
pass "add respects a widget the user moved"

# String entries are a valid layout form and must count as present too.
write_config <<'JSON'
{
  "version": 1,
  "bar": { "layout": { "center": ["omarchy.keyboard-layout", "omarchy.clock"] } },
  "plugins": []
}
JSON
add "$widget" --after omarchy.clock >/dev/null
[[ $(ids center) == '["omarchy.keyboard-layout","omarchy.clock"]' ]] ||
  fail "add recognizes string-form entries" "$(ids center)"
pass "add recognizes string-form entries"

plain_bar
if add omarchy.not-a-widget --after omarchy.clock >/dev/null 2>&1; then
  fail "add rejects an unknown widget id"
fi
pass "add rejects an unknown widget id"
