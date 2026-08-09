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

put() {
  HOME="$home" omarchy-bar put "$@"
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
put "$widget" --after omarchy.clock >/dev/null
[[ $(ids center) == '["omarchy.clock","omarchy.keyboard-layout","omarchy.weather"]' ]] ||
  fail "put places a widget after the named one" "$(ids center)"
pass "put places a widget after the named one"

# Running it again must not add a second copy or move the first.
put "$widget" --section right >/dev/null
[[ $(ids center) == '["omarchy.clock","omarchy.keyboard-layout","omarchy.weather"]' && $(ids right) == '["omarchy.tray"]' ]] ||
  fail "put leaves a widget already on the bar alone" "center: $(ids center) right: $(ids right)"
pass "put leaves a widget already on the bar alone"

plain_bar
put "$widget" --before omarchy.weather >/dev/null
[[ $(ids center) == '["omarchy.clock","omarchy.keyboard-layout","omarchy.weather"]' ]] ||
  fail "put places a widget before the named one" "$(ids center)"
pass "put places a widget before the named one"

# The anchor is looked for in the target section, so one that isn't there just
# leaves the widget at the end rather than failing the command.
plain_bar
put "$widget" --after omarchy.nonexistent >/dev/null
[[ $(ids center) == '["omarchy.clock","omarchy.weather","omarchy.keyboard-layout"]' ]] ||
  fail "put falls back to the end of the section" "$(ids center)"
pass "put falls back to the end of the section"

plain_bar
put "$widget" right >/dev/null
[[ $(ids right) == '["omarchy.tray","omarchy.keyboard-layout"]' ]] ||
  fail "put takes a positional section" "$(ids right)"
pass "put takes a positional section"

plain_bar
put "$widget" --section right --index 0 >/dev/null
[[ $(ids right) == '["omarchy.keyboard-layout","omarchy.tray"]' ]] ||
  fail "put honors an explicit index" "$(ids right)"
pass "put honors an explicit index"

# A widget the user moved elsewhere counts as present wherever it sits.
write_config <<'JSON'
{
  "version": 1,
  "bar": { "layout": { "left": [{ "id": "omarchy.keyboard-layout" }], "center": [{ "id": "omarchy.clock" }] } },
  "plugins": []
}
JSON
put "$widget" --after omarchy.clock >/dev/null
[[ $(ids left) == '["omarchy.keyboard-layout"]' && $(ids center) == '["omarchy.clock"]' ]] ||
  fail "put respects a widget the user moved" "left: $(ids left) center: $(ids center)"
pass "put respects a widget the user moved"

# String entries are a valid layout form and must count as present too.
write_config <<'JSON'
{
  "version": 1,
  "bar": { "layout": { "center": ["omarchy.keyboard-layout", "omarchy.clock"] } },
  "plugins": []
}
JSON
put "$widget" --after omarchy.clock >/dev/null
[[ $(ids center) == '["omarchy.keyboard-layout","omarchy.clock"]' ]] ||
  fail "put recognizes string-form entries" "$(ids center)"
pass "put recognizes string-form entries"

plain_bar
if put omarchy.not-a-widget --after omarchy.clock >/dev/null 2>&1; then
  fail "put rejects an unknown widget id"
fi
pass "put rejects an unknown widget id"

# ------------------------------------------------- configs the shell ignores
#
# The shell takes a user shell.json only when it parses, says version 1, and
# carries a bar layout. Otherwise the shipped defaults are what is on screen,
# and those already carry the default widgets, so there is nothing to add and
# nothing to write. Getting this wrong replaces the bar the user sees with a
# layout holding only the new widget.

assert_untouched() {
  local label="$1" contents="$2"
  write_config <<<"$contents"
  put "$widget" --after omarchy.clock >/dev/null
  [[ $(cat "$config") == "$contents" ]] || fail "$label" "$(cat "$config")"
  pass "$label"
}

assert_untouched "put leaves an unparsable config alone" '{ not json'
assert_untouched "put leaves a config with no bar alone" '{"version":1,"idle":{"lock":600}}'
assert_untouched "put leaves a config the shell ignores alone" '{"version":2,"bar":{"layout":{"center":[]}}}'

# Same shape of config, but adding a widget the defaults do not carry: the bar
# the user sees has to survive, so the defaults are seeded rather than started
# from empty, and the rest of their settings are left alone.
defaults_ids() {
  jq -c --arg section "$1" '[.bar.layout[$section][] | .id // .]' "$ROOT/config/omarchy/shell.json"
}

write_config <<'JSON'
{"version":1,"idle":{"lock":600}}
JSON
put omarchy.dropbox >/dev/null
[[ $(ids center) == "$(defaults_ids center)" && $(ids left) == "$(defaults_ids left)" ]] ||
  fail "put seeds the default layout before placing a new widget" "center: $(ids center)"
[[ $(ids right) == "$(jq -c '. + ["omarchy.dropbox"]' <<<"$(defaults_ids right)")" ]] ||
  fail "put places the new widget in its own default section" "right: $(ids right)"
[[ $(jq -c '.idle' "$config") == '{"lock":600}' ]] ||
  fail "add keeps the rest of the config" "$(cat "$config")"
pass "put seeds the default layout before placing a new widget"

# A widget the user disabled stays off the bar rather than landing in a layout
# the registry still refuses to load.
write_config <<'JSON'
{
  "version": 1,
  "bar": { "layout": { "center": [{ "id": "omarchy.clock" }] } },
  "disabledPlugins": ["omarchy.keyboard-layout"],
  "plugins": []
}
JSON
put "$widget" --after omarchy.clock >/dev/null
[[ $(ids center) == '["omarchy.clock"]' ]] ||
  fail "put leaves a disabled widget off the bar" "$(ids center)"
pass "put leaves a disabled widget off the bar"

# One malformed hand-installed manifest fails the whole plugin catalog, which
# must not stop a widget being placed.
plain_bar
mkdir -p "$home/.config/omarchy/plugins/broken"
echo '{ not a manifest' >"$home/.config/omarchy/plugins/broken/manifest.json"
put "$widget" --after omarchy.clock >/dev/null 2>&1
[[ $(ids center) == '["omarchy.clock","omarchy.keyboard-layout","omarchy.weather"]' ]] ||
  fail "put survives an unreadable plugin catalog" "$(ids center)"
pass "put survives an unreadable plugin catalog"
