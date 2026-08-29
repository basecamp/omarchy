#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command file
require_command magick

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
fixture_dir="$test_tmp/fixtures"
download_tmp="$test_tmp/downloads"
mkdir -p "$mock_bin" "$test_home" "$fixture_dir" "$download_tmp"

magick -size 4x4 xc:black "$fixture_dir/icon.png"
magick -size 4x4 xc:black "$fixture_dir/icon.webp"
printf 'not an image\n' >"$fixture_dir/invalid.txt"

cat >"$mock_bin/curl" <<'SH'
#!/bin/bash

output=""
url="${!#}"

while (( $# > 0 )); do
  case "$1" in
  -o)
    output="$2"
    shift 2
    ;;
  *) shift ;;
  esac
done

if [[ -z $output ]]; then
  printf '<link rel="apple-touch-icon" href="/icon.webp">\n'
  exit 0
fi

case "$url" in
*/icon.png) cp "$ICON_PNG_FIXTURE" "$output" ;;
*/icon.webp) cp "$ICON_WEBP_FIXTURE" "$output" ;;
*/invalid.txt) cp "$INVALID_FIXTURE" "$output" ;;
*) exit 1 ;;
esac
SH

cat >"$mock_bin/gtk-update-icon-cache" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$mock_bin"/*

export HOME="$test_home"
export ICON_PNG_FIXTURE="$fixture_dir/icon.png"
export ICON_WEBP_FIXTURE="$fixture_dir/icon.webp"
export INVALID_FIXTURE="$fixture_dir/invalid.txt"
export OMARCHY_PATH="$ROOT"
export PATH="$mock_bin:$PATH"
export TMPDIR="$download_tmp"

assert_png_icon() {
  local name="$1"
  local slug="$2"
  local icon="$HOME/.local/share/icons/hicolor/256x256/apps/$slug.png"
  local desktop="$HOME/.local/share/applications/$name.desktop"

  [[ $(file -b --mime-type "$icon") == "image/png" ]] ||
    fail "$name stores a real PNG icon"
  grep -Fqx "Icon=$slug" "$desktop" ||
    fail "$name desktop entry references its themed icon name"
  pass "$name stores and references a real PNG icon"
}

"$ROOT/bin/omarchy-webapp-install" "Explicit WebP" https://example.com https://example.com/icon.webp
assert_png_icon "Explicit WebP" explicit-webp

"$ROOT/bin/omarchy-webapp-install" "Automatic WebP" https://example.com ""
assert_png_icon "Automatic WebP" automatic-webp

"$ROOT/bin/omarchy-webapp-install" "Explicit PNG" https://example.com https://example.com/icon.png
assert_png_icon "Explicit PNG" explicit-png

cat >"$mock_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin/omarchy-cmd-present"

"$ROOT/bin/omarchy-webapp-install" "Unavailable Converter" https://example.com https://example.com/icon.webp
fallback_icon="$HOME/.local/share/icons/hicolor/256x256/apps/unavailable-converter.png"
fallback_desktop="$HOME/.local/share/applications/Unavailable Converter.desktop"
[[ $(file -b --mime-type "$fallback_icon") == "image/webp" ]] ||
  fail "web app installer preserves the original image when conversion is unavailable"
grep -Fqx "Icon=unavailable-converter" "$fallback_desktop" ||
  fail "web app installer creates a desktop entry when conversion is unavailable"
pass "web app installer creates the app when icon conversion is unavailable"

cat >"$mock_bin/mv" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin/mv"

if "$ROOT/bin/omarchy-webapp-install" "Failed Icon Install" https://example.com https://example.com/icon.webp >"$test_tmp/failed-install-output"; then
  fail "web app installer reports a failed fallback icon installation"
fi
[[ ! -e $HOME/.local/share/applications/Failed\ Icon\ Install.desktop ]] ||
  fail "web app installer creates no desktop entry after a failed icon installation"
pass "web app installer reports a failed fallback icon installation"

if "$ROOT/bin/omarchy-webapp-install" "Invalid Icon" https://example.com https://example.com/invalid.txt >"$test_tmp/invalid-icon-output"; then
  fail "web app installer rejects a non-image download"
fi

[[ ! -e $HOME/.local/share/icons/hicolor/256x256/apps/invalid-icon.png ]] ||
  fail "web app installer leaves no invalid destination file"
[[ ! -e $HOME/.local/share/applications/Invalid\ Icon.desktop ]] ||
  fail "web app installer creates no desktop entry after an invalid download"
pass "web app installer rejects invalid downloads without leaving output"

shopt -s nullglob
temporary_downloads=("$download_tmp"/*)
shopt -u nullglob
(( ${#temporary_downloads[@]} == 0 )) ||
  fail "web app installer cleans up temporary downloads"
pass "web app installer cleans up temporary downloads"
