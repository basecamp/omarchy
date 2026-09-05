#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home/.local/share/applications"

write_desktop() {
  local name="$1" exec_line="$2"

  cat >"$test_home/.local/share/applications/$name" <<EOF
[Desktop Entry]
Exec=$exec_line
EOF
}

cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
printf '%s\n' "${BROWSER:-$OMARCHY_TEST_BROWSER}"
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf 'notify:%s\n' "$*" >>"$OMARCHY_TEST_LAUNCH"
SH

cat >"$mock_bin/sed" <<'SH'
#!/bin/bash
# Hide the real system desktop entries so only the mock HOME ones resolve.
args=()
for arg in "$@"; do
  [[ $arg == /usr/share/applications/* ]] || args+=("$arg")
done
if ((${#args[@]} == 0)); then
  exit 0
fi
exec /usr/bin/sed "${args[@]}"
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
  : >"$test_tmp/launch"
  HOME="$test_home" PATH="$mock_bin:$PATH" OMARCHY_TEST_BROWSER="$1" \
    OMARCHY_TEST_LAUNCH="$test_tmp/launch" \
    bash "$ROOT/bin/omarchy-launch-webapp" "${@:2}"
}

assert_launch() {
  local expected="$1" description="$2"

  grep -F -- "$expected" "$test_tmp/launch" >/dev/null ||
    fail "$description" "launch: $(cat "$test_tmp/launch")"
  pass "$description"
}

write_desktop "firefox.desktop" "/usr/lib/firefox/firefox %u"
write_desktop "com.google.Chrome.desktop" "/opt/google/chrome/chrome %U"
write_desktop "google-chrome.desktop" "/usr/bin/google-chrome-stable %U"

launch_webapp "com.google.Chrome.desktop" "https://messenger.com"
assert_launch "/opt/google/chrome/chrome --app=https://messenger.com" \
  "a chromium-family default browser is used with --app"

launch_webapp "firefox.desktop" "https://messenger.com"
assert_launch "/usr/bin/google-chrome-stable --app=https://messenger.com" \
  "a firefox default falls back to an installed chromium-family browser"

launch_webapp "chromium.desktop" "https://messenger.com"
assert_launch "/usr/bin/google-chrome-stable --app=https://messenger.com" \
  "a default browser without an installed entry falls back to an installed chromium-family browser"

launch_webapp "firefox.desktop" "https://messenger.com" "--user-data-dir=/tmp/x"
assert_launch "/usr/bin/google-chrome-stable --app=https://messenger.com --user-data-dir=/tmp/x" \
  "extra arguments pass through to the browser"

write_desktop "evil-chrome.desktop" "/usr/bin/evil-chrome %u"
export BROWSER=evil-chrome.desktop
launch_webapp "firefox.desktop" "https://messenger.com"
unset BROWSER
assert_launch "/usr/bin/google-chrome-stable --app=https://messenger.com" \
  "the BROWSER environment variable does not skew browser detection"

rm "$test_home/.local/share/applications/google-chrome.desktop" "$test_home/.local/share/applications/com.google.Chrome.desktop"

output=$(launch_webapp "firefox.desktop" "https://messenger.com" 2>&1) && status=0 || status=$?
[[ $status -eq 1 ]] || fail "a missing chromium-family browser exits with an error" "exit: $status, output: $output"
[[ $output == *"no Chromium-family browser installed"* ]] ||
  fail "a missing chromium-family browser prints a clear error" "output: $output"
grep -F "notify:" "$test_tmp/launch" >/dev/null ||
  fail "a missing chromium-family browser sends a notification" "log: $(cat "$test_tmp/launch")"
pass "a missing chromium-family browser exits with a clear error and sends a notification"
