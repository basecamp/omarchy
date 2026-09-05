#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ $1 == "clients" ]]; then
  printf '%s\n' "$OMARCHY_TEST_CLIENTS_JSON"
elif [[ $1 == "dispatch" ]]; then
  printf '%s\n' "$2" >"$OMARCHY_TEST_FOCUS_DISPATCH"
fi
SH
cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_LAUNCH"
SH
cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_LAUNCH"
SH
chmod +x "$mock_bin"/*

dispatch_log="$test_tmp/dispatch"
launch_log="$test_tmp/launch"

run_launcher() {
  local launcher="$1"
  local clients_json="$2"
  shift 2
  rm -f "$dispatch_log" "$launch_log"
  PATH="$mock_bin:$PATH" OMARCHY_TEST_CLIENTS_JSON="$clients_json" \
    OMARCHY_TEST_FOCUS_DISPATCH="$dispatch_log" OMARCHY_TEST_LAUNCH="$launch_log" \
    bash "$ROOT/bin/$launcher" "$@"
}

clients_json='[
  {"address":"0xplugin","class":"org.quickshell","title":"Spotify"},
  {"address":"0xspotify","class":"Spotify","title":"Liked Songs"}
]'
run_launcher omarchy-launch-spotify "$clients_json"
grep -F 'address:0xspotify' "$dispatch_log" >/dev/null || fail "Spotify launcher skips the Quickshell plugin window"
pass "Spotify launcher focuses the official client behind a plugin window"

clients_json='[
  {"address":"0xplugin","class":"org.quickshell","title":"Spotify"},
  {"address":"0xbrowser","class":"chromium","title":"Spotify - Chromium"},
  {"address":"0xterminal","title":"Spotify"},
  {"address":"0xmissing","class":null,"title":"Spotify"}
]'
run_launcher omarchy-launch-spotify "$clients_json"
[[ ! -e $dispatch_log ]] || fail "Spotify launcher ignores title-only and missing-class matches"
[[ -e $launch_log ]] || fail "Spotify launcher starts Spotify or its installer when no client exists"
pass "Spotify launcher safely ignores non-client Spotify titles"

clients_json='[
  {"address":"0xsignal","class":"signal","title":"Alice"},
  {"address":"0xother","class":"signal-desktop","title":"Bob"}
]'
run_launcher omarchy-launch-signal "$clients_json"
grep -F 'address:0xsignal' "$dispatch_log" >/dev/null || fail "Signal launcher identifies a client whose conversation title omits Signal"
pass "Signal launcher identifies the signal class"

clients_json='[{"address":"0xsignal-desktop","class":"signal-desktop","title":"Alice"}]'
run_launcher omarchy-launch-signal "$clients_json"
grep -F 'address:0xsignal-desktop' "$dispatch_log" >/dev/null || fail "Signal launcher identifies the signal-desktop class"
pass "Signal launcher supports the signal-desktop class"

clients_json='[
  {"address":"0xplugin","class":"ORG.QUICKSHELL","title":"Signal"},
  {"address":"0xbrowser","class":"chromium","title":"Signal"}
]'
run_launcher omarchy-launch-signal "$clients_json"
[[ ! -e $dispatch_log ]] || fail "Signal launcher ignores title-only matches"
[[ -e $launch_log ]] || fail "Signal launcher starts Signal or its installer when no client exists"
pass "Signal launcher ignores Quickshell and other application titles"

clients_json='[
  {"address":"0xplugin","class":"org.quickshell","title":"Calendar"},
  {"address":"0xwebapp","class":"chromium","title":"Calendar"}
]'
run_launcher omarchy-launch-or-focus "$clients_json" Calendar 'calendar-launch-command'
grep -F 'address:0xwebapp' "$dispatch_log" >/dev/null || fail "generic launcher skips Quickshell before matching a web app title"
pass "generic launcher preserves title matching for Chromium web apps"

clients_json='[{"address":"0xplugin","class":"Org.Quickshell","title":"Calendar"}]'
run_launcher omarchy-launch-or-focus "$clients_json" Calendar 'calendar-launch-command'
[[ ! -e $dispatch_log ]] || fail "generic launcher ignores a case-insensitive Quickshell class"
grep -F 'calendar-launch-command' "$launch_log" >/dev/null || fail "generic launcher starts the command when only a Quickshell match exists"
pass "generic launcher excludes org.quickshell windows case-insensitively"
