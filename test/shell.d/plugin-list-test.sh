#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' '[
  {"id": "omarchy.clock", "name": "Clock", "enabled": true, "firstParty": true, "kinds": ["bar-widget"]},
  {"id": "acme.weather", "name": "Weather", "enabled": false, "firstParty": false, "kinds": ["bar-widget", "service"]},
  {"id": "tester.bar", "name": "Tester Bar", "enabled": true, "firstParty": false, "kinds": ["bar"]}
]'
SH
chmod +x "$TMPDIR/bin/omarchy-shell"

list_plugins() {
  PATH="$TMPDIR/bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-plugin-list" "$@"
}

list_plugins --json --source=third-party | jq -e 'length == 2 and all(.[]; .firstParty == false)' >/dev/null ||
  fail "--source=third-party --json lists only third-party plugins"
pass "--source=third-party --json lists only third-party plugins"

list_plugins --json --source=first-party | jq -e 'length == 1 and .[0].id == "omarchy.clock"' >/dev/null ||
  fail "--source=first-party --json lists only first-party plugins"
pass "--source=first-party --json lists only first-party plugins"

list_plugins --json --state=enabled | jq -e 'length == 2 and all(.[]; .enabled)' >/dev/null ||
  fail "--state=enabled --json lists only enabled plugins"
pass "--state=enabled --json lists only enabled plugins"

list_plugins --json --state=disabled | jq -e 'length == 1 and .[0].id == "acme.weather"' >/dev/null ||
  fail "--state=disabled --json lists only disabled plugins"
pass "--state=disabled --json lists only disabled plugins"

list_plugins --json --kinds=service | jq -e 'length == 1 and .[0].id == "acme.weather"' >/dev/null ||
  fail "--kinds=service --json matches a plugin that has service among its kinds"
pass "--kinds=service --json matches a plugin that has service among its kinds"

list_plugins --json --kinds=bar-widget | jq -e 'length == 2 and all(.[]; .kinds | index("bar-widget") != null)' >/dev/null ||
  fail "--kinds=bar-widget --json matches every plugin carrying that kind"
pass "--kinds=bar-widget --json matches every plugin carrying that kind"

list_plugins --json --kinds=bar-widget,service | jq -e 'length == 1 and .[0].id == "acme.weather"' >/dev/null ||
  fail "--kinds=bar-widget,service --json matches a plugin that carries every listed kind"
pass "--kinds=bar-widget,service --json matches a plugin that carries every listed kind"

list_plugins --json --kinds=service,bar | jq -e 'length == 0' >/dev/null ||
  fail "--kinds=service,bar --json skips plugins missing any listed kind"
pass "--kinds=service,bar --json skips plugins missing any listed kind"

list_plugins --json | jq -e 'length == 3' >/dev/null ||
  fail "plain --json still lists every plugin"
pass "plain --json still lists every plugin"

output=$(list_plugins --source=third-party)
grep -q '^acme.weather' <<<"$output" || fail "--source=third-party table lists third-party plugins" "$output"
grep -q '^tester.bar' <<<"$output" || fail "--source=third-party table lists third-party plugins" "$output"
if grep -q '^omarchy.clock' <<<"$output"; then
  fail "--source=third-party table omits first-party plugins"
fi
pass "--source=third-party table lists only third-party plugins"

if list_plugins --source=bogus >/dev/null 2>&1; then
  fail "an unknown --source value is rejected"
fi
pass "an unknown --source value is rejected"

if list_plugins --state=bogus >/dev/null 2>&1; then
  fail "an unknown --state value is rejected"
fi
pass "an unknown --state value is rejected"

output=$(list_plugins --help)
grep -q -- '--source=<first-party|third-party>' <<<"$output" || fail "help shows --source" "$output"
grep -q -- '--state=<enabled|disabled>' <<<"$output" || fail "help shows --state" "$output"
grep -Fq -- '--kinds=<kind[,kind...]>' <<<"$output" || fail "help shows --kinds" "$output"
pass "help shows all filter options"
