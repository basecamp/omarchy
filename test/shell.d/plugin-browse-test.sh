#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
catalog_file="$test_tmp/catalog.json"
action_log="$test_tmp/actions"
notification_log="$test_tmp/notifications"
installed_file="$test_tmp/installed.json"
payload_file="$test_tmp/marketplace-payload.json"
catalog_payload_file="$test_tmp/marketplace-catalog.json"
summon_log="$test_tmp/summon"
curl_log="$test_tmp/curl"
cache_dir="$test_tmp/cache"
mkdir -p "$mock_bin"

cat >"$mock_bin/curl" <<'SH'
#!/bin/bash

set -euo pipefail

url="${!#}"
if [[ $url == "https://plugins.omarchy.org/catalog.json" ]]; then
  [[ ${OMARCHY_TEST_CURL_FAIL:-false} == "true" ]] && exit 1
  cat "$OMARCHY_TEST_CATALOG"
  exit 0
fi

printf '%s\n' "$url" >>"$OMARCHY_TEST_CURL_LOG"
output=""
for (( index = 1; index <= $#; index++ )); do
  if [[ ${!index} == "-o" ]]; then
    (( index++ ))
    output=${!index}
    break
  fi
done

[[ -n $output ]] || exit 1
mkdir -p "$(dirname -- "$output")"
printf 'thumbnail for %s\n' "$url" >"$output"
SH

cat >"$mock_bin/omarchy-plugin-list" <<'SH'
#!/bin/bash
cat "$OMARCHY_TEST_INSTALLED"
SH

cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash

set -euo pipefail

[[ $1 == "shell" && $2 == "summon" && $3 == "omarchy.plugin-marketplace" ]] || exit 1
printf '%s\0' "$@" >"$OMARCHY_TEST_SUMMON"
printf '%s' "$4" >"$OMARCHY_TEST_PAYLOAD"
cat "$(jq -r '.catalogFile' <<<"$4")" >"$OMARCHY_TEST_CATALOG_PAYLOAD"
printf '%s\t%s\n' "${OMARCHY_TEST_ACTION:-}" "$OMARCHY_TEST_SELECTED_ID" >"$(jq -r '.selectionFile' <<<"$4")"
touch "$(jq -r '.doneFile' <<<"$4")"
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
export XDG_CACHE_HOME="$cache_dir"
export OMARCHY_TEST_CATALOG="$catalog_file"
export OMARCHY_TEST_SELECTED_ID="acme.clock"
export OMARCHY_TEST_ACTION=""
export OMARCHY_TEST_PAYLOAD="$payload_file"
export OMARCHY_TEST_CATALOG_PAYLOAD="$catalog_payload_file"
export OMARCHY_TEST_SUMMON="$summon_log"
export OMARCHY_TEST_CURL_LOG="$curl_log"
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
      "installAvailable": true,
      "previewImage": "https://plugins.omarchy.org/previews/clock-detail.png",
      "previewThumbnail": "https://plugins.omarchy.org/previews/clock.png"
    },
    {
      "id": "acme.suite",
      "name": "Desktop Suite",
      "repo": "https://github.com/acme/suite.git",
      "sourceType": "community",
      "installAvailable": false
    },
    {
      "id": "omarchy.builtin",
      "name": "Built-in",
      "sourceType": "builtin"
    }
  ]
}
JSON

omarchy-plugin-browse
mapfile -d '' -t action <"$action_log"
[[ ${action[0]} == "terminal" && ${action[1]} == "omarchy-plugin-add https://github.com/acme/clock.git" ]] ||
  fail "plugin marketplace routes installable repositories through the guarded installer" "${action[*]}"
mapfile -d '' -t summon <"$summon_log"
[[ ${summon[0]} == "shell" && ${summon[1]} == "summon" && ${summon[2]} == "omarchy.plugin-marketplace" ]] ||
  fail "plugin marketplace summons the native browser" "${summon[*]}"

jq -e --arg cache "$cache_dir" '
  (.catalogFile | type == "string" and length > 0)
  and (.selectionFile | type == "string" and length > 0)
  and (.doneFile | type == "string" and length > 0)
' "$payload_file" >/dev/null || fail "plugin marketplace receives catalog and IPC files"

jq -e '
  (length == 2)
  and (map(.id) == ["acme.clock", "acme.suite"])
  and (map(select(.id == "acme.clock")) | .[0].installed == false)
  and (map(select(.id == "acme.suite")) | .[0].installed == false)
  and (.[] | select(.id == "acme.clock") | .previewPath == "https://plugins.omarchy.org/previews/clock-detail.png")
  and (.[] | select(.id == "acme.clock") | .previewImages == ["https://plugins.omarchy.org/previews/clock-detail.png"])
  and (.[] | select(.id == "acme.suite") | .previewPath == "")
  and (.[] | select(.id == "acme.suite") | .previewImages == [])
' "$catalog_payload_file" >/dev/null || fail "plugin marketplace receives community catalog entries with installed state"

pass "plugin marketplace summons the native browser with community catalog data"

printf '[{"id":"acme.clock"}]\n' >"$installed_file"
export OMARCHY_TEST_SELECTED_ID="acme.clock"
omarchy-plugin-browse
mapfile -d '' -t action <"$action_log"
[[ ${action[0]} == "webapp" && ${action[1]} == "https://plugins.omarchy.org/plugin.html?id=acme.clock" ]] ||
  fail "installed marketplace entries open their detail page instead of reinstalling" "${action[*]}"
jq -e '.[] | select(.id == "acme.clock") | .installed == true' "$catalog_payload_file" >/dev/null ||
  fail "plugin marketplace marks installed community plugins in its payload"
pass "installed marketplace entries open their detail page"

export OMARCHY_TEST_ACTION="remove"
omarchy-plugin-browse
mapfile -d '' -t action <"$action_log"
[[ ${action[0]} == "terminal" && ${action[1]} == "omarchy-plugin-remove acme.clock" ]] ||
  fail "installed marketplace entries route uninstalls through the guarded remover" "${action[*]}"
pass "installed marketplace entries can be removed"
export OMARCHY_TEST_ACTION=""

printf '[]\n' >"$installed_file"
export OMARCHY_TEST_SELECTED_ID="acme.suite"
omarchy-plugin-browse
mapfile -d '' -t action <"$action_log"
[[ ${action[0]} == "webapp" && ${action[1]} == "https://plugins.omarchy.org/plugin.html?id=acme.suite" ]] ||
  fail "manual marketplace entries open their detail page" "${action[*]}"
pass "manual marketplace entries open their detail page"

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
