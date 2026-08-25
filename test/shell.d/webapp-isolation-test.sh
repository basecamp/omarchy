#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command sed

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
mock_bin="$test_tmp/bin"
launch_log="$test_tmp/launch.log"
mkdir -p "$mock_bin" "$test_home/.local/share/applications"

cat >"$test_home/.local/share/applications/chromium.desktop" <<'EOF'
[Desktop Entry]
Exec=chromium %U
EOF

cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
echo chromium.desktop
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_LAUNCH_LOG"
SH

cat >"$mock_bin/gtk-update-icon-cache" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/update-desktop-database" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$mock_bin"/*

icon_file="$test_tmp/icon.png"
printf 'fake-icon' >"$icon_file"

export HOME="$test_home"
export PATH="$mock_bin:$PATH"
export OMARCHY_TEST_LAUNCH_LOG="$launch_log"
export OMARCHY_REMOVE_NOTIFY=false

bash "$ROOT/bin/omarchy-webapp-install" "Mail App" "https://mail.example.com" "$icon_file" --isolate

desktop="$test_home/.local/share/applications/Mail App.desktop"
[[ -f $desktop ]] || fail "isolated install writes a desktop file"
grep -Fq 'Exec=omarchy-launch-webapp https://mail.example.com --isolate=mail-app' "$desktop" ||
  fail "isolated install writes --isolate into Exec" "$(cat "$desktop")"
pass "isolated install writes --isolate into Exec"

bash "$ROOT/bin/omarchy-webapp-install" "Shared App" "https://shared.example.com" "$icon_file"
shared_desktop="$test_home/.local/share/applications/Shared App.desktop"
grep -Fq 'Exec=omarchy-launch-webapp https://shared.example.com' "$shared_desktop" ||
  fail "non-isolated install writes a plain Exec" "$(cat "$shared_desktop")"
if grep -q -- '--isolate' "$shared_desktop"; then
  fail "non-isolated install does not pass --isolate" "$(cat "$shared_desktop")"
fi
pass "non-isolated install leaves Exec unisolated"

: >"$launch_log"
bash "$ROOT/bin/omarchy-launch-webapp" "https://mail.example.com" --isolate=mail-app
grep -Fq -- '--app=https://mail.example.com' "$launch_log" ||
  fail "isolated launch keeps --app" "$(cat "$launch_log")"
grep -Fq -- "--user-data-dir=$test_home/.local/share/omarchy/webapps/mail-app" "$launch_log" ||
  fail "isolated launch passes --user-data-dir" "$(cat "$launch_log")"
[[ -d $test_home/.local/share/omarchy/webapps/mail-app ]] ||
  fail "isolated launch creates the profile directory"
pass "isolated launch uses a separate user-data-dir"

: >"$launch_log"
bash "$ROOT/bin/omarchy-launch-webapp" "https://shared.example.com"
grep -Fq -- '--app=https://shared.example.com' "$launch_log" ||
  fail "plain launch keeps --app" "$(cat "$launch_log")"
if grep -q -- '--user-data-dir' "$launch_log"; then
  fail "plain launch does not pass --user-data-dir" "$(cat "$launch_log")"
fi
pass "plain launch does not isolate the browser process"

mkdir -p "$test_home/.local/share/omarchy/webapps/mail-app"
printf 'profile' >"$test_home/.local/share/omarchy/webapps/mail-app/marker"
bash "$ROOT/bin/omarchy-webapp-remove" "Mail App"
[[ ! -e $desktop ]] || fail "remove deletes the desktop file"
[[ ! -d $test_home/.local/share/omarchy/webapps/mail-app ]] ||
  fail "remove deletes the isolated profile"
pass "remove deletes the isolated profile"

bash "$ROOT/bin/omarchy-webapp-install" "Another App" "https://other.example.com" "$icon_file" --isolate
mkdir -p "$test_home/.local/share/omarchy/webapps/another-app"
printf 'profile' >"$test_home/.local/share/omarchy/webapps/another-app/marker"
bash "$ROOT/bin/omarchy-webapp-remove-all" "$test_home/.local/share/applications"
[[ ! -d $test_home/.local/share/omarchy/webapps/another-app ]] ||
  fail "remove-all deletes isolated profiles"
pass "remove-all deletes isolated profiles"
