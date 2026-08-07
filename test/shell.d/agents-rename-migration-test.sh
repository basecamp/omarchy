#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

migration="$ROOT/migrations/1786099804.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/omarchy-agent-usage-update" <<'STUB'
#!/bin/bash

echo run >>"$USAGE_UPDATES"
STUB

chmod +x "$test_dir/bin/"*

export USAGE_UPDATES="$test_dir/usage-updates"

home="$test_dir/home"
config="$home/.config/omarchy/shell.json"

run_migration() {
  : >"$USAGE_UPDATES"
  HOME="$home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

mkdir -p "$home/.config/omarchy" "$home/.cache/omarchy/model-usage"
cat >"$config" <<'JSON'
{
  "bar": {
    "layout": {
      "center": ["omarchy.model-usage"],
      "right": [
        { "id": "omarchy.tray" },
        { "id": "omarchy.model-usage", "syncMode": "On", "syncDir": "~/Sync/agent-usage" }
      ]
    }
  },
  "disabledPlugins": ["omarchy.model-usage", "omarchy.weather"]
}
JSON

run_migration

[[ $(jq -c '.bar.layout.right[1]' "$config") == '{"id":"omarchy.agents","syncMode":"On","syncDir":"~/Sync/agent-usage"}' ]] ||
  fail "migration renames the widget and keeps its settings" "$(cat "$config")"
pass "migration renames the widget and keeps its settings"

[[ $(jq -c '.bar.layout.center' "$config") == '["omarchy.agents"]' ]] ||
  fail "migration renames string-form entries" "$(cat "$config")"
pass "migration renames string-form entries"

[[ $(jq -c '.disabledPlugins' "$config") == '["omarchy.agents","omarchy.weather"]' ]] ||
  fail "migration keeps a disabled widget disabled" "$(cat "$config")"
pass "migration keeps a disabled widget disabled"

[[ ! -e $home/.cache/omarchy/model-usage ]] ||
  fail "migration drops the old scanner cache"
pass "migration drops the old scanner cache"

(($(wc -l <"$USAGE_UPDATES") == 1)) || fail "migration primes the usage data files"
pass "migration primes the usage data files"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "migration is idempotent" "$(cat "$config")"
pass "migration is idempotent"

# A config the migration cannot parse is left alone rather than truncated.
printf '{ not json' >"$config"
run_migration

[[ $(cat "$config") == '{ not json' ]] || fail "migration leaves an unparsable config untouched" "$(cat "$config")"
pass "migration leaves an unparsable config untouched"
