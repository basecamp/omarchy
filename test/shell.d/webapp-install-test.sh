#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command file
require_command magick

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
mkdir -p "$home/.local/share/applications"

install_webapp() {
  HOME="$home" "$ROOT/bin/omarchy-webapp-install" "$@"
}

desktop_for() {
  printf '%s' "$home/.local/share/applications/$1.desktop"
}

if install_webapp "Example" "https://example.com" "webapp" >"$tmpdir/out" 2>"$tmpdir/err"; then
  :
else
  fail "webapp install accepts an https URL" "$(cat "$tmpdir/err")"
fi

desktop=$(desktop_for Example)
[[ -f $desktop ]] || fail "webapp install writes a desktop file"
grep -Fxq 'Name=Example' "$desktop" || fail "webapp install writes the app name"
grep -Fxq 'Exec=omarchy-launch-webapp "https://example.com"' "$desktop" ||
  fail "webapp install launches the https URL" "$(cat "$desktop")"
pass "webapp install writes an https desktop entry"

if install_webapp "Plain" "example.org/app" "webapp" >"$tmpdir/out" 2>"$tmpdir/err"; then
  :
else
  fail "webapp install prefixes a schemeless URL with https" "$(cat "$tmpdir/err")"
fi
grep -Fxq 'Exec=omarchy-launch-webapp "https://example.org/app"' "$(desktop_for Plain)" ||
  fail "webapp install stores the prefixed https URL" "$(cat "$(desktop_for Plain)")"
pass "webapp install prefixes a schemeless URL with https"

if install_webapp "Local" "https://localhost:47990" "webapp" "omarchy-launch-webapp https://localhost:47990 --ignore-certificate-errors" >"$tmpdir/out" 2>"$tmpdir/err"; then
  :
else
  fail "webapp install keeps a custom https exec" "$(cat "$tmpdir/err")"
fi
grep -Fxq 'Exec=omarchy-launch-webapp https://localhost:47990 --ignore-certificate-errors' "$(desktop_for Local)" ||
  fail "webapp install writes the custom exec" "$(cat "$(desktop_for Local)")"
pass "webapp install keeps a custom https exec"

for url in "javascript:alert(1)" "file:///etc/passwd" "data:text/html,hi" "ftp://example.com" "ext://x"; do
  if install_webapp "Bad" "$url" "webapp" >"$tmpdir/out" 2>"$tmpdir/err"; then
    fail "webapp install refuses '$url'"
  fi
  grep -Fq 'must be http or https' "$tmpdir/err" ||
    fail "webapp install names the scheme refusal for '$url'" "$(cat "$tmpdir/err")"
  [[ ! -e $(desktop_for Bad) ]] || fail "webapp install does not write a desktop file for '$url'"
done
pass "webapp install refuses non-http(s) URLs"

# Raw whitespace is not valid URL data, and before Exec argument quoting it
# split browser flags or additional URLs into separate arguments.
for url in \
  " javascript:alert(1)" \
  " file:///etc/passwd" \
  "https://example.com data:text/html,hi" \
  "https://example.com/ --user-agent=INJECTION_PROOF_MARKER_12345"; do
  if install_webapp "Sneak" "$url" "webapp" >"$tmpdir/out" 2>"$tmpdir/err"; then
    fail "webapp install refuses whitespace in '$url'" "$(cat "$(desktop_for Sneak)")"
  fi
  grep -Fq 'must not contain whitespace' "$tmpdir/err" ||
    fail "webapp install names the whitespace refusal for '$url'" "$(cat "$tmpdir/err")"
  [[ ! -e $(desktop_for Sneak) ]] || fail "webapp install writes no desktop file for '$url'"
done
pass "webapp install refuses a URL carrying whitespace"

# Schemes are case-insensitive, and HTTPS://example.com installed before the
# scheme test existed.
if install_webapp "Upper" "HTTPS://example.com" "webapp" >"$tmpdir/out" 2>"$tmpdir/err"; then
  :
else
  fail "webapp install accepts an uppercase scheme" "$(cat "$tmpdir/err")"
fi
grep -Fxq 'Exec=omarchy-launch-webapp "HTTPS://example.com"' "$(desktop_for Upper)" ||
  fail "webapp install keeps the uppercase scheme" "$(cat "$(desktop_for Upper)")"
pass "webapp install accepts an uppercase http scheme"

# The interactive prompt fetches the site's icon, so a refused URL must be
# refused before anything dereferences it.
stubs="$tmpdir/stubs"
mkdir -p "$stubs"

cat >"$stubs/gum" <<'GUM'
#!/bin/bash
count=$(cat "$GUM_COUNT" 2>/dev/null || echo 0)
count=$((count + 1))
printf '%s\n' "$count" >"$GUM_COUNT"
sed -n "${count}p" "$GUM_ANSWERS"
GUM

cat >"$stubs/curl" <<'CURL'
#!/bin/bash
printf '%s\n' "$*" >>"$CURL_LOG"
exit 1
CURL

chmod +x "$stubs/gum" "$stubs/curl"

printf 'Evil\nfile:///etc/passwd\n' >"$tmpdir/answers"
: >"$tmpdir/gum-count"
: >"$tmpdir/curl-log"

if GUM_ANSWERS="$tmpdir/answers" GUM_COUNT="$tmpdir/gum-count" CURL_LOG="$tmpdir/curl-log" \
  PATH="$stubs:$PATH" HOME="$home" "$ROOT/bin/omarchy-webapp-install" \
  >"$tmpdir/out" 2>"$tmpdir/err"; then
  fail "interactive webapp install refuses a file: URL" "$(cat "$tmpdir/out")"
fi
grep -Fq 'must be http or https' "$tmpdir/err" ||
  fail "interactive webapp install names the scheme refusal" "$(cat "$tmpdir/err")"
[[ ! -s $tmpdir/curl-log ]] ||
  fail "interactive webapp install refuses before fetching the URL" "$(cat "$tmpdir/curl-log")"
[[ ! -e $(desktop_for Evil) ]] || fail "interactive webapp install writes no desktop file"
pass "interactive webapp install refuses a bad URL before fetching it"

# Sites commonly declare an SVG through rel="icon" without providing an
# apple-touch-icon. The installer should discover it and store a real PNG for
# the hicolor icon theme rather than SVG data under a misleading .png name.
icon_stubs="$tmpdir/icon-stubs"
mkdir -p "$icon_stubs"

cat >"$tmpdir/icon-page.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <link href="/favicon.svg" type="image/svg+xml" rel="icon">
  </head>
</html>
HTML

cat >"$tmpdir/favicon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" fill="#2296f3"/>
</svg>
SVG

cat >"$icon_stubs/curl" <<'CURL'
#!/bin/bash

output=""
url="${!#}"

while (( $# > 0 )); do
  case $1 in
  -o)
    output="$2"
    shift 2
    ;;
  *) shift ;;
  esac
done

if [[ -z $output ]]; then
  cat "$ICON_PAGE_FIXTURE"
elif [[ $url == "https://example.com/favicon.svg" ]]; then
  cp "$ICON_SVG_FIXTURE" "$output"
else
  exit 1
fi
CURL

cat >"$icon_stubs/gtk-update-icon-cache" <<'CACHE'
#!/bin/bash
exit 0
CACHE

chmod +x "$icon_stubs"/*

if ICON_PAGE_FIXTURE="$tmpdir/icon-page.html" ICON_SVG_FIXTURE="$tmpdir/favicon.svg" \
  PATH="$icon_stubs:$PATH" install_webapp "SVG Icon" "https://example.com/app" "" \
  >"$tmpdir/out" 2>"$tmpdir/err"; then
  :
else
  fail "webapp install discovers a standard SVG favicon" "$(cat "$tmpdir/err")"
fi

icon="$home/.local/share/icons/hicolor/256x256/apps/svg-icon.png"
[[ $(file -b --mime-type "$icon") == "image/png" ]] ||
  fail "webapp install stores the SVG favicon as a real PNG" "$(file "$icon")"
grep -Fxq 'Icon=svg-icon' "$(desktop_for "SVG Icon")" ||
  fail "webapp install references the converted favicon" "$(cat "$(desktop_for "SVG Icon")")"
pass "webapp install discovers and converts a standard SVG favicon"
