#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

migration="$ROOT/migrations/1787636621.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
config="$home/.config/omarchy/shell.json"

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

# The shipped default minus the widget is what every machine installed before
# this migration has on disk.
write_config() {
  rm -rf "$home"
  mkdir -p "$home/.config/omarchy"
  jq "${1:-.}" "$ROOT/config/omarchy/shell.json" >"$config"
}

without_widget='del(.bar.layout[][] | select((if type == "object" then .id else . end) == "omarchy.snippets"))'

ids() {
  jq -c --arg section "$1" '[.bar.layout[$section][]? | if type == "object" then .id else . end]' "$config"
}

# ------------------------------------------------------------------ shipped default

jq -e '[.bar.layout.right[].id] | index("omarchy.snippets")' "$ROOT/config/omarchy/shell.json" >/dev/null ||
  fail "shipped config puts the snippets widget in the bar"
pass "shipped config puts the snippets widget in the bar"

jq -e '[.bar.layout.left[]? | if type == "object" then .id else . end] | index("omarchy.snippets") | not' \
  "$ROOT/config/omarchy/shell.json" >/dev/null ||
  fail "shipped config does not also leave the snippets widget in the left section"
pass "shipped config does not also leave the snippets widget in the left section"

# ------------------------------------------------------------------ placement

write_config "$without_widget"
run_migration

[[ $(ids right) == '["omarchy.tray","omarchy.snippets","omarchy.agents","omarchy.bluetooth","omarchy.network","omarchy.audio","omarchy.monitor","omarchy.power"]' ]] ||
  fail "migration inserts the snippets widget after the tray" "$(ids right)"
pass "migration inserts the snippets widget after the tray"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "migration is idempotent" "$(ids right)"
pass "migration is idempotent"

# ------------------------------------------------------------------ curated bars

# A user who already placed the widget keeps it exactly where they put it, in
# whichever section, and never gets a second copy.
write_config "$without_widget | .bar.layout.left += [{ id: \"omarchy.snippets\" }]"
run_migration

[[ $(ids left) == *'"omarchy.snippets"'* ]] || fail "migration leaves a user-placed widget alone" "$(ids left)"
[[ $(ids right) != *'"omarchy.snippets"'* ]] || fail "migration does not add a second copy" "$(ids right)"
pass "migration respects a widget the user already placed"

# Layouts written before entries grew options are bare id strings.
write_config "$without_widget | .bar.layout.right = [\"omarchy.tray\", \"omarchy.audio\"]"
run_migration

[[ $(ids right) == '["omarchy.tray","omarchy.snippets","omarchy.audio"]' ]] ||
  fail "migration reads string-form entries" "$(ids right)"
pass "migration reads string-form entries"

# A tray dropped from the right section must not strand the widget or drop it.
write_config "$without_widget | del(.bar.layout.right[] | select(.id == \"omarchy.tray\"))"
run_migration

[[ $(ids right) == '["omarchy.snippets",'* ]] || fail "migration places the widget without a tray" "$(ids right)"
pass "migration places the widget without a tray"

# ------------------------------------------------------------------ everything else

write_config "$without_widget"
cp "$config" "$test_dir/before.json"
run_migration

diff <(jq -S 'del(.bar.layout.right)' "$test_dir/before.json") <(jq -S 'del(.bar.layout.right)' "$config") >/dev/null ||
  fail "migration touches nothing but the right section" "$(diff <(jq -S . "$test_dir/before.json") <(jq -S . "$config"))"
pass "migration touches nothing but the right section"

# A config the migration cannot parse is left alone rather than truncated.
rm -rf "$home"
mkdir -p "$home/.config/omarchy"
printf '{ not json' >"$config"
run_migration

[[ $(cat "$config") == '{ not json' ]] || fail "migration leaves an unparsable config untouched" "$(cat "$config")"
pass "migration leaves an unparsable config untouched"

# No config file at all (a genuinely fresh install materializes the shipped
# default itself, but a login before that materialization must not crash).
rm -rf "$home"
HOME="$home" bash -euo pipefail "$migration" >/dev/null
[[ ! -e "$config" ]] || fail "migration does not create a config file where none existed"
pass "migration does not create a config file where none existed"
