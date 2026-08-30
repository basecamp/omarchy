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

brave_desktop="$home/.local/share/applications/brave-browser.desktop"

install_brave() {
  printf '%s\n' \
    '[Desktop Entry]' \
    'Name=Brave' \
    'Exec=/opt/brave/brave-bin %u' \
    'Type=Application' \
    >"$brave_desktop"
}

empty_launch_log() {
  : >"$OMARCHY_TEST_LOG"
}

launch_webapp() {
  HOME="$home" PATH="$mock_bin:$PATH" OMARCHY_TEST_LOG="$launch_log" \
    "$ROOT/bin/omarchy-launch-webapp" "$@"
}

# A whitelisted Chromium default with a resolvable launcher is launched as an
# app window; extra arguments after the URL are forwarded.
set_default_browser "brave-browser.desktop"
install_brave
empty_launch_log
launch_webapp "https://web.whatsapp.com/" "--flag" >"$tmpdir/out" 2>"$tmpdir/err" ||
  fail "webapp launch succeeds with a Chromium default browser" "$(cat "$tmpdir/err")"
grep -Fxq 'launch:uwsm-app -- /opt/brave/brave-bin --app=https://web.whatsapp.com/ --flag' \
  "$tmpdir/launch.log" ||
  fail "webapp launch uses the default browser Exec with --app" "$(cat "$tmpdir/launch.log")"
pass "webapp launch forwards the URL and flags to the default Chromium browser"

# The default browser is not a supported one, but a Chromium-family browser is
# installed anyway (e.g. Brave installed while the default is Zen). The launcher
# should fall back to the installed Chromium browser rather than give up.
set_default_browser "zen.desktop"
install_brave
empty_launch_log
launch_webapp "https://web.whatsapp.com/" >"$tmpdir/out2" 2>"$tmpdir/err2" ||
  fail "webapp launch falls back to an installed Chromium browser" "$(cat "$tmpdir/err2")"
grep -Fxq 'launch:uwsm-app -- /opt/brave/brave-bin --app=https://web.whatsapp.com/' \
  "$tmpdir/launch.log" ||
  fail "webapp launch uses the installed browser when the default is unsupported" "$(cat "$tmpdir/launch.log")"
pass "webapp launch falls back to an installed Chromium browser when the default is unsupported"
