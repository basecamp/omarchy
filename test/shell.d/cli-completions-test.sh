#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT

export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export PATH="$ROOT/bin:$PATH"
unset XDG_CONFIG_HOME

mkdir -p "$test_home/.config/omarchy/plugins/acme.weather" \
  "$test_home/.config/omarchy/plugins/acme.neon-bar"

cat >"$test_home/.config/omarchy/plugins/acme.weather/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "acme.weather",
  "name": "Weather",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": { "displayName": "Weather", "defaultSection": "center" }
}
JSON

cat >"$test_home/.config/omarchy/plugins/acme.neon-bar/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "acme.neon-bar",
  "name": "Neon bar",
  "kinds": ["bar"],
  "entryPoints": { "bar": "Bar.qml" }
}
JSON

cat >"$test_home/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [{ "id": "omarchy.clock" }],
      "center": [],
      "right": ["acme.weather"]
    }
  }
}
JSON

source "$ROOT/default/bash/completions"

complete_omarchy() {
  local line="$1"
  COMP_LINE="$line"
  COMP_POINT=${#line}
  read -r -a COMP_WORDS <<<"$line"
  if [[ $line == *" " ]]; then
    COMP_WORDS+=("")
  fi
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMPREPLY=()
  set +e
  _omarchy_complete
  set -e
}

has_reply() {
  local want="$1"
  local got
  for got in "${COMPREPLY[@]+"${COMPREPLY[@]}"}"; do
    [[ $got == "$want" ]] && return 0
  done
  return 1
}

assert_has() {
  local want="$1"
  local line="$2"
  has_reply "$want" || fail "completion for [$line] includes $want" "${COMPREPLY[*]:-<none>}"
}

assert_lacks() {
  local want="$1"
  local line="$2"
  has_reply "$want" && fail "completion for [$line] does not include $want" "${COMPREPLY[*]:-<none>}"
  return 0
}

complete_omarchy "omarchy bar "
assert_has set "omarchy bar "
assert_has move "omarchy bar "
assert_has put "omarchy bar "
assert_has use "omarchy bar "
assert_has position "omarchy bar "
assert_lacks text "omarchy bar "
pass "omarchy bar completes its verbs instead of hidden bar-text-color"

complete_omarchy "omarchy bar s"
assert_has set "omarchy bar s"
assert_lacks text "omarchy bar s"
pass "omarchy bar s completes set"

complete_omarchy "omarchy bar position "
assert_has top "omarchy bar position "
assert_has bottom "omarchy bar position "
pass "omarchy bar position completes edges"

complete_omarchy "omarchy bar set "
assert_has omarchy.clock "omarchy bar set "
assert_has acme.weather "omarchy bar set "
assert_lacks omarchy.media "omarchy bar set "
assert_lacks acme.neon-bar "omarchy bar set "
pass "omarchy bar set completes widgets on the bar"

complete_omarchy "omarchy bar move "
assert_has omarchy.clock "omarchy bar move "
assert_lacks omarchy.media "omarchy bar move "
pass "omarchy bar move completes widgets on the bar"

complete_omarchy "omarchy bar put "
assert_has omarchy.clock "omarchy bar put "
assert_has omarchy.media "omarchy bar put "
assert_has acme.weather "omarchy bar put "
assert_lacks acme.neon-bar "omarchy bar put "
pass "omarchy bar put completes bar-widget plugin ids"

complete_omarchy "omarchy bar use "
assert_has omarchy.bar "omarchy bar use "
assert_has acme.neon-bar "omarchy bar use "
assert_lacks omarchy.clock "omarchy bar use "
pass "omarchy bar use completes bar option ids"

complete_omarchy "omarchy bar set omarchy.clock format HH:mm "
assert_has --json "omarchy bar set omarchy.clock format HH:mm "
assert_has --section "omarchy bar set omarchy.clock format HH:mm "
pass "omarchy bar set offers --json and placement flags after the value"

complete_omarchy "omarchy bar move omarchy.clock --section "
assert_has left "omarchy bar move omarchy.clock --section "
assert_has center "omarchy bar move omarchy.clock --section "
assert_has right "omarchy bar move omarchy.clock --section "
pass "omarchy bar --section completes left/center/right"

complete_omarchy "omarchy bar put omarchy.media --after "
assert_has omarchy.clock "omarchy bar put omarchy.media --after "
assert_has acme.weather "omarchy bar put omarchy.media --after "
pass "omarchy bar --after completes widgets on the bar"

complete_omarchy "omarchy plugin "
assert_has enable "omarchy plugin "
assert_has disable "omarchy plugin "
assert_has clone "omarchy plugin "
assert_lacks catalog "omarchy plugin "
pass "omarchy plugin completes its verbs and hides catalog"

complete_omarchy "omarchy plugin enable "
assert_has acme.weather "omarchy plugin enable "
assert_has acme.neon-bar "omarchy plugin enable "
assert_has omarchy.clock "omarchy plugin enable "
pass "omarchy plugin enable completes catalog ids"

complete_omarchy "omarchy plugin disable "
assert_has acme.weather "omarchy plugin disable "
assert_has omarchy.clock "omarchy plugin disable "
pass "omarchy plugin disable completes catalog ids"

complete_omarchy "omarchy plugin clone "
assert_has omarchy.clock "omarchy plugin clone "
assert_lacks acme.weather "omarchy plugin clone "
pass "omarchy plugin clone completes first-party plugin ids"

complete_omarchy "omarchy plugin remove "
assert_has acme.weather "omarchy plugin remove "
assert_has acme.neon-bar "omarchy plugin remove "
assert_lacks omarchy.clock "omarchy plugin remove "
pass "omarchy plugin remove completes installed user plugin ids"
