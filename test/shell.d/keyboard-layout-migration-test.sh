#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"

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
  rm -rf "$home"
  mkdir -p "$home/.config/omarchy"
  cat >"$config"
}

ids() {
  jq -c '[.bar.layout.center[]? | if type == "object" then .id else . end]' "$config"
}

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

run_migration
[[ $(ids) == '["omarchy.clock","omarchy.keyboard-layout","omarchy.weather"]' ]] ||
  fail "migration puts the widget right of the clock" "$(ids)"
pass "migration puts the widget right of the clock"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "migration is idempotent" "$(cat "$config")"
pass "migration is idempotent"

# A bar the user curated keeps the widget where they put it.
write_config <<'JSON'
{
  "version": 1,
  "bar": { "layout": { "center": [{ "id": "omarchy.clock" }], "right": [{ "id": "omarchy.keyboard-layout" }] } },
  "plugins": []
}
JSON

run_migration
[[ $(ids) == '["omarchy.clock"]' ]] || fail "migration does not add a second copy" "$(cat "$config")"
pass "migration does not add a second copy"

# Nothing to anchor to still lands the widget on the bar.
write_config <<'JSON'
{
  "version": 1,
  "bar": { "layout": { "center": [{ "id": "omarchy.weather" }] } },
  "plugins": []
}
JSON

run_migration
[[ $(ids) == '["omarchy.weather","omarchy.keyboard-layout"]' ]] ||
  fail "migration falls back to the end of the center section" "$(ids)"
pass "migration falls back to the end of the center section"
