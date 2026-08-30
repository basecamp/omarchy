#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
home="$tmpdir/home"
launch_log="$tmpdir/launch.log"
export OMARCHY_TEST_LOG="$launch_log"
mkdir -p "$mock_bin" "$home/.local/share/applications"

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf 'launch:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH
chmod +x "$mock_bin/setsid"

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf 'notify:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH
chmod +x "$mock_bin/omarchy-notification-send"

set_default_browser() {
  local browser="$1"
  cat >"$mock_bin/xdg-settings" <<SH
#!/bin/bash
printf '%s\n' "$browser"
SH
  chmod +x "$mock_bin/xdg-settings"
}

set_default_browser "zen.desktop"

empty_launch_log() {
  : >"$OMARCHY_TEST_LOG"
}

# With the default browser outside the whitelist and no Chromium-family
# browser installed, the launcher falls back to chromium.desktop, whose Exec
# cannot be resolved. It must name the problem instead of launching a nonsense
# --app=... invocation that the app daemon then rejects at runtime.
if HOME="$home" PATH="$mock_bin:$PATH" OMARCHY_TEST_LOG="$launch_log" \
  "$ROOT/bin/omarchy-launch-webapp" "https://web.whatsapp.com/" \
  >"$tmpdir/out" 2>"$tmpdir/err"; then
  fail "webapp launch fails without a Chromium browser"
fi
grep -Fq 'Chromium-based browser' "$tmpdir/err" ||
  fail "webapp launch names the missing browser" "$(cat "$tmpdir/err")"
grep -Fq 'notify:' "$tmpdir/launch.log" ||
  fail "webapp launch shows a desktop notification" "$(cat "$tmpdir/launch.log")"
! grep -q '^launch:' "$tmpdir/launch.log" ||
  fail "webapp launch does not exec a browser without one installed" "$(cat "$tmpdir/launch.log")"
pass "webapp launch warns when no Chromium browser is installed"

# A whitelisted browser with a resolvable launcher is launched as an app window;
# extra arguments after the URL are forwarded.
set_default_browser "brave-browser.desktop"
printf '%s\n' \
  '[Desktop Entry]' \
  'Name=Brave' \
  'Exec=/opt/brave/brave-bin %u' \
  'Type=Application' \
  >"$home/.local/share/applications/brave-browser.desktop"

empty_launch_log
HOME="$home" PATH="$mock_bin:$PATH" OMARCHY_TEST_LOG="$launch_log" \
  "$ROOT/bin/omarchy-launch-webapp" "https://web.whatsapp.com/" "--flag" \
  >"$tmpdir/out2" 2>"$tmpdir/err2" ||
  fail "webapp launch succeeds with a Chromium browser" "$(cat "$tmpdir/err2")"
grep -Fxq 'launch:uwsm-app -- /opt/brave/brave-bin --app=https://web.whatsapp.com/ --flag' \
  "$tmpdir/launch.log" ||
  fail "webapp launch uses the browser Exec with --app" "$(cat "$tmpdir/launch.log")"
pass "webapp launch forwards the URL and flags to the Chromium browser"
