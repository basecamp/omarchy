#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home/.local/share/applications"

cat >"$test_home/.local/share/applications/opera.desktop" <<'EOF'
[Desktop Entry]
Exec=opera %U
EOF

cat >"$test_home/.local/share/applications/chromium.desktop" <<'EOF'
[Desktop Entry]
Exec=chromium %U
EOF

cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
echo "${OMARCHY_TEST_BROWSER:-chromium.desktop}"
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$mock_bin/uwsm-app" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_LAUNCH"
SH

chmod +x "$mock_bin"/*

launch_webapp() {
  HOME="$test_home" PATH="$mock_bin:$PATH" \
    OMARCHY_TEST_BROWSER="$1" OMARCHY_TEST_LAUNCH="$test_tmp/launch" \
    bash "$ROOT/bin/omarchy-launch-webapp" "$2"
}

launch_webapp opera.desktop "https://chatgpt.com"
[[ $(<"$test_tmp/launch") == "-- opera https://chatgpt.com" ]] ||
  fail "Opera webapps launch as a tab URL" "$(<"$test_tmp/launch")"
pass "Opera webapps launch as a tab URL"

launch_webapp chromium.desktop "https://chatgpt.com"
[[ $(<"$test_tmp/launch") == "-- chromium --app=https://chatgpt.com" ]] ||
  fail "Chromium webapps still use --app=" "$(<"$test_tmp/launch")"
pass "Chromium webapps still use --app="
