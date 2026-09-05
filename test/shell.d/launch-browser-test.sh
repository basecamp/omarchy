#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home/.local/share/applications"

cat >"$test_home/.local/share/applications/chromium.desktop" <<'EOF'
[Desktop Entry]
Exec=chromium %U
EOF

cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
[[ -z ${BROWSER:-} ]] || printf '%s\n' "$BROWSER" >"$OMARCHY_TEST_XDG_SETTINGS_BROWSER"
[[ ${OMARCHY_TEST_XDG_SETTINGS_EMPTY:-0} == "1" ]] || echo "${OMARCHY_TEST_XDG_SETTINGS_DEFAULT:-chromium.desktop}"
SH
cat >"$mock_bin/xdg-mime" <<'SH'
#!/bin/bash
if [[ $* == "query default x-scheme-handler/https" ]]; then
  echo chromium.desktop
fi
SH
cat >"$mock_bin/chromium" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/systemd-run" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_BROWSER_LAUNCH"
SH
cat >"$mock_bin/omarchy-hyprland-focus-app" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >"$OMARCHY_TEST_BROWSER_FOCUS"
SH
chmod +x "$mock_bin"/*

launch_log="$test_tmp/launch"
focus_log="$test_tmp/focus"
xdg_settings_browser="$test_tmp/xdg-settings-browser"
HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
  OMARCHY_TEST_BROWSER_LAUNCH="$launch_log" OMARCHY_TEST_BROWSER_FOCUS="$focus_log" \
  bash "$ROOT/bin/omarchy-launch-browser"

[[ ! -e $focus_log ]] || fail "browser launcher leaves a new window on the current workspace"

HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
  OMARCHY_TEST_BROWSER_LAUNCH="$launch_log" OMARCHY_TEST_BROWSER_FOCUS="$focus_log" \
  bash "$ROOT/bin/omarchy-launch-browser" --private

[[ ! -e $focus_log ]] || fail "private browser launcher leaves a new window on the current workspace"

HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
  OMARCHY_TEST_BROWSER_LAUNCH="$launch_log" OMARCHY_TEST_BROWSER_FOCUS="$focus_log" \
  bash "$ROOT/bin/omarchy-launch-browser" "https://example.test/authorize"

grep -F 'https://example.test/authorize' "$launch_log" >/dev/null || fail "browser launcher passes through the URL"
grep -Fx '^chromium.*$' "$focus_log" >/dev/null || fail "browser launcher focuses the default browser window"

rm -f "$focus_log" "$xdg_settings_browser"

HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
  BROWSER=omarchy-launch-browser OMARCHY_TEST_XDG_SETTINGS_EMPTY=1 \
  OMARCHY_TEST_BROWSER_LAUNCH="$launch_log" OMARCHY_TEST_BROWSER_FOCUS="$focus_log" \
  OMARCHY_TEST_XDG_SETTINGS_BROWSER="$xdg_settings_browser" \
  bash "$ROOT/bin/omarchy-launch-browser" "https://example.test/fallback"

grep -F 'https://example.test/fallback' "$launch_log" >/dev/null ||
  fail "browser launcher falls back to the HTTPS handler when xdg-settings is empty"
[[ ! -e $xdg_settings_browser ]] ||
  fail "browser launcher unsets BROWSER before reading xdg-settings"
grep -Fx '^chromium.*$' "$focus_log" >/dev/null ||
  fail "browser launcher focuses the browser resolved from the HTTPS handler"

pass "browser launcher follows opened links to the browser workspace"

# A Flatpak browser lives under Flatpak's exported data dir, not /usr, and its
# Exec is the whole `flatpak run ...` line with the URL slot wrapped in @@u/@@.
flatpak_share="$test_tmp/flatpak/exports/share"
mkdir -p "$flatpak_share/applications"
cat >"$flatpak_share/applications/net.waterfox.waterfox.desktop" <<'EOF'
[Desktop Entry]
Name=Waterfox
Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=waterfox --file-forwarding net.waterfox.waterfox @@u %u @@
EOF
cat >"$mock_bin/flatpak" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$mock_bin/flatpak"

rm -f "$focus_log"
HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
  XDG_DATA_DIRS="$flatpak_share:/usr/share" \
  OMARCHY_TEST_XDG_SETTINGS_DEFAULT=net.waterfox.waterfox.desktop \
  OMARCHY_TEST_BROWSER_LAUNCH="$launch_log" OMARCHY_TEST_BROWSER_FOCUS="$focus_log" \
  bash "$ROOT/bin/omarchy-launch-browser" "https://example.test/flatpak"

grep -F -- '--collect' "$launch_log" >/dev/null || fail "flatpak browser launcher still detaches the browser"
grep -F -- 'uwsm-app -- /usr/bin/flatpak run --branch=stable --arch=x86_64 --command=waterfox --file-forwarding net.waterfox.waterfox https://example.test/flatpak' "$launch_log" >/dev/null ||
  fail "browser launcher runs a Flatpak browser through its full flatpak command" "$(cat "$launch_log")"
if grep -F -- '@@' "$launch_log" >/dev/null; then
  fail "browser launcher strips Flatpak's file-forwarding markers" "$(cat "$launch_log")"
fi
grep -Fx '^(net.waterfox.waterfox|waterfox).*$' "$focus_log" >/dev/null ||
  fail "browser launcher focuses a Flatpak browser by its app id or command" "$(cat "$focus_log")"

pass "browser launcher runs and focuses a Flatpak browser"
