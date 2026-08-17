#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1786874363.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
home="$test_dir/home"
config="$home/.config/omarchy/shell.json"

write_config() {
  rm -rf "$home"
  mkdir -p "$(dirname "$config")"
  jq "$1" "$ROOT/config/omarchy/shell.json" >"$config"
}

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

ids() {
  jq -c --arg section "$1" '[.bar.layout[$section][]? | if type == "object" then .id else . end]' "$config"
}

without_input='del(.bar.layout[][] | select((if type == "object" then .id else . end) == "omarchy.input"))'

write_config "$without_input"
run_migration
[[ $(ids right) == '["omarchy.tray","omarchy.agents","omarchy.bluetooth","omarchy.network","omarchy.input","omarchy.audio","omarchy.monitor","omarchy.power"]' ]] ||
  fail "input migration places the panel after network" "$(ids right)"
pass "input migration places the panel after network"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "input migration is idempotent"
pass "input migration is idempotent"

write_config "$without_input | .bar.layout.left += [{ id: \"omarchy.input\" }]"
run_migration
[[ $(ids left) == *'"omarchy.input"'* && $(ids right) != *'"omarchy.input"'* ]] ||
  fail "input migration respects an existing placement"
pass "input migration respects an existing placement"
