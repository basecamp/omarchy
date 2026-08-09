#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

migration="$ROOT/migrations/1786279107.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
config="$home/.config/omarchy/shell.json"

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

write_config() {
  mkdir -p "$home/.config/omarchy"
  cat >"$config"
}

write_config <<'JSON'
{
  "bar": {
    "layout": {
      "left": [{ "id": "omarchy.menu" }],
      "center": [{ "id": "omarchy.clock" }, { "id": "omarchy.weather" }],
      "right": [{ "id": "omarchy.tray" }]
    }
  }
}
JSON

run_migration

[[ $(jq -c '[.bar.layout.center[].id]' "$config") == '["omarchy.clock","omarchy.keyboard-layout","omarchy.weather"]' ]] ||
  fail "migration adds the widget right of the clock" "$(cat "$config")"
pass "migration adds the widget right of the clock"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "migration is idempotent" "$(cat "$config")"
pass "migration is idempotent"

# A bar the user curated keeps the widget where they put it.
write_config <<'JSON'
{
  "bar": {
    "layout": {
      "center": [{ "id": "omarchy.clock" }],
      "right": [{ "id": "omarchy.keyboard-layout" }]
    }
  }
}
JSON

run_migration

[[ $(jq -c '.bar.layout.center' "$config") == '[{"id":"omarchy.clock"}]' &&
  $(jq -c '.bar.layout.right' "$config") == '[{"id":"omarchy.keyboard-layout"}]' ]] ||
  fail "migration does not add a second copy" "$(cat "$config")"
pass "migration does not add a second copy"

# String-form entries count as present too.
write_config <<'JSON'
{
  "bar": { "layout": { "center": ["omarchy.keyboard-layout"] } }
}
JSON

run_migration

[[ $(jq -c '.bar.layout.center' "$config") == '["omarchy.keyboard-layout"]' ]] ||
  fail "migration recognizes string-form entries" "$(cat "$config")"
pass "migration recognizes string-form entries"

# A widget the user disabled on purpose stays off the bar.
write_config <<'JSON'
{
  "bar": { "layout": { "center": [{ "id": "omarchy.clock" }] } },
  "disabledPlugins": ["omarchy.keyboard-layout"]
}
JSON

run_migration

[[ $(jq -c '.bar.layout.center' "$config") == '[{"id":"omarchy.clock"}]' ]] ||
  fail "migration leaves a disabled widget off the bar" "$(cat "$config")"
pass "migration leaves a disabled widget off the bar"

# No clock to anchor to: the widget still lands on the bar.
write_config <<'JSON'
{
  "bar": { "layout": { "center": [{ "id": "omarchy.weather" }] } }
}
JSON

run_migration

[[ $(jq -c '[.bar.layout.center[].id]' "$config") == '["omarchy.keyboard-layout","omarchy.weather"]' ]] ||
  fail "migration falls back to the section head without a clock" "$(cat "$config")"
pass "migration falls back to the section head without a clock"

# A config the migration cannot parse is left alone rather than truncated.
printf '{ not json' >"$config"
run_migration

[[ $(cat "$config") == '{ not json' ]] || fail "migration leaves an unparsable config untouched" "$(cat "$config")"
pass "migration leaves an unparsable config untouched"

# No config at all is not an error.
rm -f "$config"
run_migration
[[ ! -e $config ]] || fail "migration does not create a config"
pass "migration does not create a config"
