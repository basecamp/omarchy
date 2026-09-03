#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
clients_json="$test_tmp/clients.json"
dispatch_log="$test_tmp/dispatch.log"
spotify_bin="$stub_bin/spotify"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ ${1:-} == clients && ${2:-} == -j ]]; then
  cat "$TEST_CLIENTS_JSON"
  exit 0
fi
if [[ ${1:-} == dispatch ]]; then
  printf '%s\n' "$*" >>"$TEST_DISPATCH_LOG"
  exit 0
fi
exit 0
SH

cat >"$spotify_bin" <<'SH'
#!/bin/bash
printf 'spotify-launched\n' >>"$TEST_SPOTIFY_LOG"
exit 0
SH

# setsid/uwsm-app: run the remaining argv so the stub spotify is reached.
cat >"$stub_bin/setsid" <<'SH'
#!/bin/bash
exec "$@"
SH
cat >"$stub_bin/uwsm-app" <<'SH'
#!/bin/bash
# omarchy-launch-spotify uses: setsid uwsm-app -- /usr/bin/spotify
while [[ $# -gt 0 && $1 != "--" ]]; do shift; done
[[ ${1:-} == "--" ]] && shift
exec "$@"
SH

chmod +x "$stub_bin"/*

export PATH="$stub_bin:$PATH"
export TEST_CLIENTS_JSON="$clients_json"
export TEST_DISPATCH_LOG="$dispatch_log"
export TEST_SPOTIFY_LOG="$test_tmp/spotify.log"

# Point the launcher at our stub binary path by placing it as /usr/bin/spotify
# is hardcoded — override via a wrapper script that we inject by rewriting PATH
# won't work for absolute /usr/bin/spotify. Patch a copy of the launcher.
launcher="$test_tmp/omarchy-launch-spotify"
sed 's|/usr/bin/spotify|'"$spotify_bin"'|g' "$ROOT/bin/omarchy-launch-spotify" >"$launcher"
chmod +x "$launcher"

: >"$dispatch_log"
: >"$TEST_SPOTIFY_LOG"

# Only Quickshell "Omarchy Spotify" — must launch the real client (#9901).
cat >"$clients_json" <<'JSON'
[
  {"class":"org.quickshell","title":"Omarchy Spotify","address":"0xqs"}
]
JSON

"$launcher" >/dev/null 2>&1 || true
[[ -s $TEST_SPOTIFY_LOG ]] || fail "spotify launches when only quickshell title matches" "$(cat "$dispatch_log")"
if grep -F '0xqs' "$dispatch_log" >/dev/null; then
  fail "must not focus the quickshell surface" "$(cat "$dispatch_log")"
fi
pass "spotify launches when only quickshell title matches"

# Real Spotify present — focus it, do not relaunch.
: >"$dispatch_log"
: >"$TEST_SPOTIFY_LOG"
cat >"$clients_json" <<'JSON'
[
  {"class":"org.quickshell","title":"Omarchy Spotify","address":"0xqs"},
  {"class":"Spotify","title":"Spotify Premium","address":"0xreal"}
]
JSON
"$launcher" >/dev/null 2>&1 || true
grep -F '0xreal' "$dispatch_log" >/dev/null ||
  fail "focuses the real Spotify client when both exist" "$(cat "$dispatch_log")"
[[ ! -s $TEST_SPOTIFY_LOG ]] || fail "does not relaunch when real Spotify is open"
pass "focuses real Spotify and ignores quickshell peer"

# Source guard on shared helpers.
for script in omarchy-launch-spotify omarchy-launch-or-focus omarchy-launch-signal; do
  grep -F 'org.quickshell' "$ROOT/bin/$script" >/dev/null ||
    fail "$script excludes org.quickshell from window match"
done
pass "launch helpers exclude org.quickshell from class/title match"
