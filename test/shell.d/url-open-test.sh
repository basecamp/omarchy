#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/dbus-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_DBUS_LOG"
[[ $* != *"NameHasOwner"* ]] || echo "   boolean true"
SH
cat >"$mock_bin/spotify" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
command -v "$1" >/dev/null
SH
cat >"$mock_bin/omarchy-launch-browser" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_BROWSER_LOG"
SH
chmod +x "$mock_bin"/*

dbus_log="$test_tmp/dbus"
browser_log="$test_tmp/browser"

run_url_open() {
  rm -f "$dbus_log" "$browser_log"
  PATH="$mock_bin:$PATH" OMARCHY_TEST_DBUS_LOG="$dbus_log" OMARCHY_TEST_BROWSER_LOG="$browser_log" \
    bash "$ROOT/bin/omarchy-url-open" "$1"
}

run_url_open "https://open.spotify.com/album/6raV6eHqsTKFsCu0vIXjQA?si=abc123"

grep -F 'OpenUri string:spotify:album:6raV6eHqsTKFsCu0vIXjQA' "$dbus_log" >/dev/null ||
  fail "album links are delivered to the Spotify client over MPRIS" "$(cat "$dbus_log")"
grep -F 'Raise' "$dbus_log" >/dev/null ||
  fail "the Spotify window is raised after delivering the link"
[[ ! -e $browser_log ]] ||
  fail "handled Spotify links do not fall through to the browser"

run_url_open "https://open.spotify.com/intl-ru/track/4uLU6hMCjMI75M1A2tKUQC"

grep -F 'OpenUri string:spotify:track:4uLU6hMCjMI75M1A2tKUQC' "$dbus_log" >/dev/null ||
  fail "localized Spotify links parse to the underlying resource" "$(cat "$dbus_log")"

run_url_open "https://example.test/album/not-spotify"

grep -F 'https://example.test/album/not-spotify' "$browser_log" >/dev/null ||
  fail "non-Spotify links open in the default browser"
[[ ! -e $dbus_log ]] ||
  fail "non-Spotify links do not touch the Spotify client"

run_url_open "https://open.spotify.com/user/someone"

grep -F 'https://open.spotify.com/user/someone' "$browser_log" >/dev/null ||
  fail "unsupported Spotify links open in the default browser"

pass "URL dispatcher routes Spotify links natively and everything else to the browser"
