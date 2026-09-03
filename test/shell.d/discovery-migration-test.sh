#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

migration="$ROOT/migrations/1788380505.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"
cat >"$test_dir/bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash

printf '%s\n' "$*" >>"$PACKAGE_ADDS"
STUB
chmod +x "$test_dir/bin/omarchy-pkg-add"

export PACKAGE_ADDS="$test_dir/package-adds"
home="$test_dir/home"
config="$home/.config/omarchy/shell.json"

run_migration() {
  HOME="$home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

mkdir -p "$home/.config/omarchy"
cat >"$config" <<'JSON'
{
  "bar": {
    "layout": {
      "left": [],
      "center": [],
      "right": [
        { "id": "omarchy.agents" },
        { "id": "io.github.tcballard.plugin-workbench", "size": "wide" },
        "omarchy.discovery",
        { "id": "omarchy.audio" }
      ]
    }
  },
  "plugins": [
    { "id": "io.github.tcballard.plugin-workbench" },
    { "id": "org.example.other" }
  ],
  "disabledPlugins": ["io.github.tcballard.plugin-workbench", "omarchy.weather"]
}
JSON

run_migration

[[ $(jq -c '.bar.layout.right' "$config") == '[{"id":"omarchy.agents"},{"id":"omarchy.discovery","size":"wide"},{"id":"omarchy.audio"}]' ]] ||
  fail "migration renames the legacy Workbench in place and removes duplicates" "$(cat "$config")"
pass "migration renames the legacy Workbench in place and removes duplicates"

[[ $(jq -c '.plugins' "$config") == '[{"id":"org.example.other"}]' ]] ||
  fail "migration removes the superseded community activation" "$(cat "$config")"
pass "migration removes the superseded community activation"

[[ $(jq -c '.disabledPlugins' "$config") == '["omarchy.discovery","omarchy.weather"]' ]] ||
  fail "migration preserves the disabled state" "$(cat "$config")"
pass "migration preserves the disabled state"

[[ $(cat "$PACKAGE_ADDS") == 'omarchy-discovery' ]] ||
  fail "migration installs the Discovery helper package" "$(cat "$PACKAGE_ADDS")"
pass "migration installs the Discovery helper package"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "migration is idempotent" "$(cat "$config")"
pass "migration is idempotent"

cat >"$config" <<'JSON'
{
  "bar": {
    "layout": {
      "left": [],
      "center": [],
      "right": [{ "id": "omarchy.agents" }, { "id": "omarchy.audio" }]
    }
  },
  "plugins": []
}
JSON

run_migration
[[ $(jq -c '.bar.layout.right' "$config") == '[{"id":"omarchy.agents"},{"id":"omarchy.discovery"},{"id":"omarchy.audio"}]' ]] ||
  fail "migration adds Discovery after agents" "$(cat "$config")"
pass "migration adds Discovery after agents"

printf '{ not json' >"$config"
run_migration
[[ $(cat "$config") == '{ not json' ]] || fail "migration leaves invalid JSON untouched"
pass "migration leaves invalid JSON untouched"
