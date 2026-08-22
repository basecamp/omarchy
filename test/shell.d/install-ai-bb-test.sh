#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
fixture_dir="$tmp_dir/fixtures"
mkdir -p "$fake_bin" "$fixture_dir"

printf 'fake-appimage' >"$fixture_dir/bb.AppImage"
printf 'fake-icon' >"$fixture_dir/bb.png"
cat >"$fixture_dir/desktop-version-linux.json" <<'JSON'
{"version":"1.2.3","files":[{"url":"bb-1.2.3-x86_64.AppImage","sha512":"BlqmG7vBM/v/ifEUJkxkZvXIkzk5g0NhfVDFb1E/bMa8QkoAlnao3z+IJBhVXx+zOiTGVDjf8XFoEXyoeEyymg=="}]}
JSON

cat >"$fake_bin/curl" <<'SCRIPT'
#!/bin/bash
while (( $# )); do
  case "$1" in
  --output)
    output="$2"
    shift 2
    ;;
  http*)
    url="$1"
    shift
    ;;
  *) shift ;;
  esac
done

case "$url" in
*/desktop-version-linux.json) cp "$TEST_FIXTURE_DIR/desktop-version-linux.json" "$output" ;;
*/bb-1.2.3-x86_64.AppImage) printf '%s' "${TEST_APP_PAYLOAD:-fake-appimage}" >"$output" ;;
*/icon.png) cp "$TEST_FIXTURE_DIR/bb.png" "$output" ;;
*) exit 1 ;;
esac
SCRIPT

cat >"$fake_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'package:%s\n' "$*" >>"$TEST_LOG"
SCRIPT

cat >"$fake_bin/update-desktop-database" <<'SCRIPT'
#!/bin/bash
printf 'desktop-database:%s\n' "$*" >>"$TEST_LOG"
SCRIPT

cat >"$fake_bin/setsid" <<'SCRIPT'
#!/bin/bash
printf 'launch:%s\n' "$*" >>"$TEST_LOG"
SCRIPT

chmod +x "$fake_bin"/*
export TEST_FIXTURE_DIR="$fixture_dir"
export TEST_LOG="$tmp_dir/log"
export PATH="$fake_bin:$PATH"

export HOME="$tmp_dir/home"
mkdir -p "$HOME"
"$ROOT/bin/omarchy-install-ai-bb" >/dev/null

app_image="$HOME/.local/share/bb/bb.AppImage"
desktop_file="$HOME/.local/share/applications/bb.desktop"
icon_file="$HOME/.local/share/icons/hicolor/1024x1024/apps/bb.png"

[[ -x $app_image && $(<"$app_image") == "fake-appimage" ]] || fail "bb installer installs the verified AppImage as an executable"
pass "bb installer installs the verified AppImage as an executable"

grep -Fqx "Exec=\"$app_image\" %U" "$desktop_file" || fail "bb installer creates a desktop entry for the AppImage"
grep -Fqx "Icon=bb" "$desktop_file" || fail "bb installer points the desktop entry at the installed icon"
[[ -f $icon_file && $(<"$icon_file") == "fake-icon" ]] || fail "bb installer installs the desktop icon"
pass "bb installer creates the desktop entry and icon"

grep -Fqx "package:fuse2" "$TEST_LOG" || fail "bb installer adds the AppImage runtime dependency"
grep -Fqx "launch:uwsm-app -- $app_image" "$TEST_LOG" || fail "bb installer launches the installed app"
pass "bb installer adds its dependency and launches the app"

export HOME="$tmp_dir/bad-home"
mkdir -p "$HOME"
if TEST_APP_PAYLOAD="tampered" "$ROOT/bin/omarchy-install-ai-bb" >/dev/null 2>&1; then
  fail "bb installer rejects an AppImage with the wrong checksum"
fi
[[ ! -e $HOME/.local/share/bb/bb.AppImage ]] || fail "bb installer leaves no app behind after a checksum failure"
pass "bb installer rejects an AppImage with the wrong checksum"
