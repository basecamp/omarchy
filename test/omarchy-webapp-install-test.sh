#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/bin/omarchy-webapp-install"
TMPDIR=""

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local description="$1"
  local file="$2"
  local expected="$3"

  if ! grep -Fq "$expected" "$file"; then
    printf 'Expected %s to contain: %s\n' "$file" "$expected" >&2
    printf 'Actual file:\n' >&2
    cat "$file" >&2
    fail "$description"
  fi

  pass "$description"
}

assert_file_equals() {
  local description="$1"
  local file="$2"
  local expected="$3"
  local actual

  actual=$(cat "$file")
  if [[ $actual != "$expected" ]]; then
    printf 'Expected %s to equal: %s\n' "$file" "$expected" >&2
    printf 'Actual: %s\n' "$actual" >&2
    fail "$description"
  fi

  pass "$description"
}

cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/curl" <<'EOF'
#!/bin/bash

set -euo pipefail

output=""
url=""

while (($#)); do
  case "$1" in
  -o)
    output="$2"
    shift 2
    ;;
  -*)
    shift
    ;;
  *)
    url="$1"
    shift
    ;;
  esac
done

printf '%s\n' "$url" >>"$CURL_LOG"

write_output() {
  local body="$1"

  if [[ -n $output ]]; then
    mkdir -p "$(dirname -- "$output")"
    printf '%s' "$body" >"$output"
  else
    printf '%s' "$body"
  fi
}

if [[ $url == "http://localhost:9001" ]]; then
  write_output '<html><head><link rel="icon" href="images/favicon.png?version=1"></head></html>'
elif [[ $url == "http://localhost:9001/images/favicon.png?version=1" ]]; then
  write_output 'local-icon'
elif [[ $url == "http://no-icon.local" ]]; then
  write_output '<html><head><title>No icon</title></head></html>'
elif [[ $url == "https://www.google.com/s2/favicons?domain=http://no-icon.local&sz=128" ]]; then
  write_output 'google-icon'
else
  printf 'Unexpected curl URL: %s\n' "$url" >&2
  exit 22
fi
EOF
chmod +x "$TMPDIR/bin/curl"

export PATH="$TMPDIR/bin:$ROOT/bin:$PATH"

reset_home() {
  local name="$1"

  export HOME="$TMPDIR/home-$name"
  export CURL_LOG="$TMPDIR/$name-curl.log"
  mkdir -p "$HOME"
  : >"$CURL_LOG"
}

reset_home local
"$SCRIPT" Penpot http://localhost:9001

desktop_file="$HOME/.local/share/applications/Penpot.desktop"
icon_file="$HOME/.local/share/applications/icons/Penpot.png"
[[ -f $desktop_file ]] || fail "two-argument install creates desktop file"
[[ -f $icon_file ]] || fail "two-argument install creates icon file"
pass "two-argument install creates files"
assert_file_contains "two-argument install writes app exec" "$desktop_file" "Exec=omarchy-launch-webapp http://localhost:9001"
assert_file_contains "two-argument install writes icon path" "$desktop_file" "Icon=$icon_file"
assert_file_equals "two-argument install uses local favicon" "$icon_file" "local-icon"
if grep -Fq 'google.com/s2/favicons' "$CURL_LOG"; then
  fail "local favicon avoids Google fallback"
fi
pass "local favicon avoids Google fallback"

reset_home google
"$SCRIPT" NoIcon http://no-icon.local

icon_file="$HOME/.local/share/applications/icons/NoIcon.png"
assert_file_equals "missing local favicon falls back to Google favicon" "$icon_file" "google-icon"

reset_home saved
mkdir -p "$HOME/.local/share/applications/icons"
printf 'saved-icon' >"$HOME/.local/share/applications/icons/Saved.png"
"$SCRIPT" SavedApp http://saved.local Saved.png

desktop_file="$HOME/.local/share/applications/SavedApp.desktop"
assert_file_contains "saved local icon name is resolved from icon directory" "$desktop_file" "Icon=$HOME/.local/share/applications/icons/Saved.png"
if [[ -s $CURL_LOG ]]; then
  fail "saved local icon name does not call curl"
fi
pass "saved local icon name does not call curl"

reset_home invalid
if "$SCRIPT" OnlyName >"$TMPDIR/invalid.out" 2>"$TMPDIR/invalid.err"; then
  fail "single-argument install fails"
fi
assert_file_contains "single-argument install explains missing URL" "$TMPDIR/invalid.out" "You must set app name and app URL!"
