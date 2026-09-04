#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home/.local/share/applications"

cat >"$test_home/.local/share/applications/firefox.desktop" <<'EOF'
[Desktop Entry]
Exec=/usr/lib/firefox/firefox %u
EOF

cat >"$test_home/.local/share/applications/chromium.desktop" <<'EOF'
[Desktop Entry]
Exec=/usr/bin/chromium %U
EOF

cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
printf '%s\n' "$BROWSER"
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$mock_bin/uwsm-app" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_WEBAPP_LAUNCH"
SH

chmod +x "$mock_bin"/*

launch_log="$test_tmp/launch"

HOME="$test_home" PATH="$mock_bin:$PATH" BROWSER=firefox.desktop \
  OMARCHY_TEST_WEBAPP_LAUNCH="$launch_log" \
  bash "$ROOT/bin/omarchy-launch-webapp" "https://messenger.com"

grep -F '/usr/lib/firefox/firefox --app=https://messenger.com' "$launch_log" >/dev/null ||
  fail "webapp launcher uses the default browser binary with --app" "launch: $(cat "$launch_log")"
pass "webapp launcher uses the default browser binary with --app"

: >"$launch_log"

HOME="$test_home" PATH="$mock_bin:$PATH" BROWSER=chromium.desktop \
  OMARCHY_TEST_WEBAPP_LAUNCH="$launch_log" \
  bash "$ROOT/bin/omarchy-launch-webapp" "https://messenger.com"

grep -F '/usr/bin/chromium --app=https://messenger.com' "$launch_log" >/dev/null ||
  fail "webapp launcher keeps the chromium fallback for unsupported browsers" "launch: $(cat "$launch_log")"
pass "webapp launcher keeps the chromium fallback for unsupported browsers"

rm -f "$test_home/.local/share/applications/chromium.desktop" "$test_home/.local/share/applications/firefox.desktop"

HOME="$test_home" PATH="$mock_bin:$PATH" BROWSER=epiphany.desktop \
  OMARCHY_TEST_WEBAPP_LAUNCH="$launch_log" \
  bash "$ROOT/bin/omarchy-launch-webapp" "https://messenger.com" >"$test_tmp/stdout" 2>"$test_tmp/stderr" &&
  fail "webapp launcher fails when no --app-capable browser is installed"

grep -F 'no browser installed' "$test_tmp/stderr" >/dev/null ||
  fail "webapp launcher reports a clear error when no --app-capable browser is installed" "$(cat "$test_tmp/stderr")"
pass "webapp launcher reports a clear error when no --app-capable browser is installed"
