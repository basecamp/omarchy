#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

migration="$ROOT/migrations/1785344985.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/omarchy-restart-shell" <<'STUB'
#!/bin/bash

echo restart >>"$SHELL_RESTARTS"
STUB

chmod +x "$test_dir/bin/"*

export SHELL_RESTARTS="$test_dir/shell-restarts"

home="$test_dir/home"
config="$home/.config/omarchy/shell.json"

run_migration() {
  : >"$SHELL_RESTARTS"
  HOME="$home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

# The shipped default minus the widget is what every machine installed before
# this migration has on disk.
write_config() {
  rm -rf "$home"
  mkdir -p "$home/.config/omarchy"
  jq "${1:-.}" "$ROOT/config/omarchy/shell.json" >"$config"
}

without_widget='del(.bar.layout[][] | select((if type == "object" then .id else . end) == "omarchy.agents"))'

ids() {
  jq -c --arg section "$1" '[.bar.layout[$section][]? | if type == "object" then .id else . end]' "$config"
}

# ------------------------------------------------------------------ shipped default

jq -e '[.bar.layout.right[].id] | index("omarchy.agents")' "$ROOT/config/omarchy/shell.json" >/dev/null ||
  fail "shipped config puts the agents widget in the bar"
pass "shipped config puts the agents widget in the bar"

# ------------------------------------------------------------------ placement

write_config "$without_widget"
run_migration

[[ $(ids right) == '["omarchy.tray","omarchy.agents","omarchy.bluetooth","omarchy.network","omarchy.audio","omarchy.monitor","omarchy.power"]' ]] ||
  fail "migration inserts the agents widget after the tray" "$(ids right)"
pass "migration inserts the agents widget after the tray"

(($(wc -l <"$SHELL_RESTARTS") == 0)) || fail "migration leaves the shell restart to omarchy update"
pass "migration leaves the shell restart to omarchy update"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "migration is idempotent" "$(ids right)"
pass "migration is idempotent"

# ------------------------------------------------------------------ curated bars

# A user who already placed the widget keeps it exactly where they put it, in
# whichever section, and never gets a second copy.
write_config "$without_widget | .bar.layout.center += [{ id: \"omarchy.agents\" }]"
run_migration

[[ $(ids center) == *'"omarchy.agents"'* ]] || fail "migration leaves a user-placed widget alone" "$(ids center)"
[[ $(ids right) != *'"omarchy.agents"'* ]] || fail "migration does not add a second copy" "$(ids right)"
pass "migration respects a widget the user already placed"

# Layouts written before entries grew options are bare id strings.
write_config "$without_widget | .bar.layout.right = [\"omarchy.tray\", \"omarchy.agents\", \"omarchy.power\"]"
run_migration

[[ $(ids right) == '["omarchy.tray","omarchy.agents","omarchy.power"]' ]] ||
  fail "migration reads string-form entries" "$(ids right)"
pass "migration reads string-form entries"

# A tray dropped from the right section must not strand the widget or drop it.
write_config "$without_widget | del(.bar.layout.right[] | select(.id == \"omarchy.tray\"))"
run_migration

[[ $(ids right) == '["omarchy.agents",'* ]] || fail "migration places the widget without a tray" "$(ids right)"
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
