#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
clients_json="$test_tmp/clients.json"
log="$test_tmp/log"
mkdir -p "$mock_bin"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ ${1:-} == clients && ${2:-} == -j ]]; then
  cat "$OMARCHY_TEST_CLIENTS"
  exit 0
fi
if [[ ${1:-} == dispatch ]]; then
  printf 'focus:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
  exit 0
fi
exit 0
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf 'launch:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf 'install:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

chmod +x "$mock_bin"/*

write_clients() {
  cat >"$clients_json"
}

run_with_clients() {
  : >"$log"
  PATH="$mock_bin:$PATH" OMARCHY_TEST_CLIENTS="$clients_json" OMARCHY_TEST_LOG="$log" "$@"
}

write_clients <<'JSON'
[
  {"address":"0xagent","class":"org.omarchy.agent","title":"Spotify player stoppt bei Fensterverschiebung"}
]
JSON

run_with_clients bash "$ROOT/bin/omarchy-launch-or-focus" spotify dummy-app
grep -Fq 'focus:' "$log" && fail "launch-or-focus ignores Omarchy agent titles" "$(cat "$log")"
grep -Fxq 'launch:dummy-app' "$log" || fail "launch-or-focus launches when only an agent title matches" "$(cat "$log")"
pass "launch-or-focus ignores Omarchy agent titles"

write_clients <<'JSON'
[
  {"address":"0xagent","class":"org.omarchy.agent","title":"Spotify player stoppt bei Fensterverschiebung"},
  {"address":"0xbrowser","class":"chromium","title":"Spotify Web Player"}
]
JSON

run_with_clients bash "$ROOT/bin/omarchy-launch-spotify"
grep -Fq 'focus:' "$log" && fail "launch-spotify matches class only" "$(cat "$log")"
grep -Fxq 'install:omarchy-install-service-spotify' "$log" || fail "launch-spotify installs when no Spotify class is present" "$(cat "$log")"
pass "launch-spotify matches class only"

write_clients <<'JSON'
[
  {"address":"0xagent","class":"org.omarchy.agent","title":"Spotify player stoppt bei Fensterverschiebung"},
  {"address":"0xspotify","class":"Spotify","title":"Spotify Premium"}
]
JSON

run_with_clients bash "$ROOT/bin/omarchy-launch-or-focus" spotify dummy-app
grep -Fq 'address:0xspotify' "$log" || fail "launch-or-focus focuses the real Spotify class" "$(cat "$log")"
grep -Fq 'address:0xagent' "$log" && fail "launch-or-focus does not focus the agent when Spotify is running" "$(cat "$log")"
pass "launch-or-focus focuses the real Spotify class"

write_clients <<'JSON'
[
  {"address":"0xagent","class":"org.omarchy.agent","title":"Spotify player stoppt bei Fensterverschiebung"},
  {"address":"0xbrowser","class":"chromium","title":"Spotify Web Player"},
  {"address":"0xspotify","class":"Spotify","title":"Spotify Premium"}
]
JSON

run_with_clients bash "$ROOT/bin/omarchy-launch-spotify"
grep -Fq 'address:0xspotify' "$log" || fail "launch-spotify focuses the Spotify class" "$(cat "$log")"
grep -Fq 'address:0xbrowser' "$log" && fail "launch-spotify does not treat a browser title as Spotify" "$(cat "$log")"
pass "launch-spotify focuses the Spotify class"

write_clients <<'JSON'
[
  {"address":"0xagent","class":"org.omarchy.agent","title":"Calendar layout tweak"},
  {"address":"0xwebapp","class":"chromium","title":"HEY Calendar"}
]
JSON

run_with_clients bash "$ROOT/bin/omarchy-launch-or-focus" Calendar dummy-webapp
grep -Fq 'address:0xwebapp' "$log" || fail "launch-or-focus still matches non-agent titles" "$(cat "$log")"
grep -Fq 'address:0xagent' "$log" && fail "launch-or-focus does not prefer the agent title" "$(cat "$log")"
pass "launch-or-focus still matches non-agent titles"

write_clients <<'JSON'
[
  {"address":"0xagent","class":"org.omarchy.agent","title":"Calendar layout tweak"}
]
JSON

run_with_clients bash "$ROOT/bin/omarchy-launch-or-focus" Calendar dummy-webapp
grep -Fxq 'launch:dummy-webapp' "$log" || fail "launch-or-focus launches when only an agent title matches Calendar" "$(cat "$log")"
pass "launch-or-focus launches when only an agent title matches Calendar"

grep -Fq '{ omarchy = "spotify" }' "$ROOT/default/hypr/bindings/applications.lua" ||
  fail "Music keybinding uses the Spotify launcher"
pass "Music keybinding uses the Spotify launcher"
