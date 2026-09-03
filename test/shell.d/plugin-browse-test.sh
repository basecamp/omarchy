#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
catalog_file="$test_tmp/catalog.json"
selection_file="$test_tmp/selection"
action_log="$test_tmp/actions"
notification_log="$test_tmp/notifications"
installed_file="$test_tmp/installed.json"
mkdir -p "$mock_bin"

cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_CURL_FAIL:-false} == "true" ]] && exit 1
cat "$OMARCHY_TEST_CATALOG"
SH

cat >"$mock_bin/omarchy-menu-select" <<'SH'
#!/bin/bash
cat >"$OMARCHY_TEST_ROWS"
cat "$OMARCHY_TEST_SELECTION"
SH

cat >"$mock_bin/omarchy-plugin-list" <<'SH'
#!/bin/bash
cat "$OMARCHY_TEST_INSTALLED"
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf 'terminal\0%s\0' "$@" >"$OMARCHY_TEST_ACTIONS"
SH

cat >"$mock_bin/omarchy-launch-webapp" <<'SH'
#!/bin/bash
printf 'webapp\0%s\0' "$@" >"$OMARCHY_TEST_ACTIONS"
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_NOTIFICATIONS"
SH

chmod +x "$mock_bin"/*
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_CATALOG="$catalog_file"
export OMARCHY_TEST_SELECTION="$selection_file"
export OMARCHY_TEST_ROWS="$test_tmp/rows"
export OMARCHY_TEST_ACTIONS="$action_log"
export OMARCHY_TEST_NOTIFICATIONS="$notification_log"
export OMARCHY_TEST_INSTALLED="$installed_file"
printf '[]\n' >"$installed_file"

cat >"$catalog_file" <<'JSON'
{
  "plugins": [
    {
      "id": "acme.clock",
      "name": "Clock",
      "repo": "https://github.com/acme/clock.git",
      "sourceType": "community",
      "installAvailable": true
    },
    {
      "id": "acme.suite",
      "name": "Desktop Suite",
      "repo": "https://github.com/acme/suite.git",
      "sourceType": "community",
      "installAvailable": false
    }
  ]
}
JSON

printf 'Clock\tacme.clock\n' >"$selection_file"
omarchy-plugin-browse
mapfile -d '' -t action <"$action_log"
[[ ${action[0]} == "terminal" && ${action[1]} == "omarchy-plugin-add https://github.com/acme/clock.git" ]] ||
  fail "plugin marketplace routes installable repositories through the guarded installer" "${action[*]}"
grep -Fq $'󰐱\tClock\tacme.clock' "$test_tmp/rows" || fail "plugin marketplace lists community plugins in the native picker"
pass "plugin marketplace browses and installs a community plugin"

printf 'Desktop Suite\tacme.suite\n' >"$selection_file"
omarchy-plugin-browse
mapfile -d '' -t action <"$action_log"
[[ ${action[0]} == "webapp" && ${action[1]} == "https://plugins.omarchy.org/plugin.html?id=acme.suite" ]] ||
  fail "manual marketplace entries open their detail page" "${action[*]}"
pass "manual marketplace entries open their detail page"

printf '[{"id":"acme.clock"}]\n' >"$installed_file"
printf 'Clock (installed)\tacme.clock\n' >"$selection_file"
omarchy-plugin-browse
mapfile -d '' -t action <"$action_log"
[[ ${action[0]} == "webapp" && ${action[1]} == "https://plugins.omarchy.org/plugin.html?id=acme.clock" ]] ||
  fail "installed marketplace entries open their detail page instead of reinstalling" "${action[*]}"
grep -Fq $'󰐱\tClock (installed)\tacme.clock' "$test_tmp/rows" || fail "installed marketplace entries are marked in the picker"
pass "installed marketplace entries are marked and not reinstalled"

export OMARCHY_TEST_CURL_FAIL=true
if omarchy-plugin-browse; then
  fail "plugin marketplace reports a failed catalog request"
fi
grep -Fq "Could not load the Omarchy plugin marketplace" "$notification_log" || fail "plugin marketplace notifies on a failed catalog request"
unset OMARCHY_TEST_CURL_FAIL

printf '{"plugins":"broken"}\n' >"$catalog_file"
if omarchy-plugin-browse; then
  fail "plugin marketplace rejects malformed catalog data"
fi
grep -Fq "returned invalid data" "$notification_log" || fail "plugin marketplace notifies on malformed catalog data"
pass "plugin marketplace handles catalog failures"
