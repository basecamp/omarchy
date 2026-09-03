#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command gio

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-launch-webapp" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >>"$OMARCHY_TEST_ARGV"
SH
chmod +x "$mock_bin"/*

export HOME="$test_tmp/home"
export PATH="$mock_bin:$PATH"
export OMARCHY_TEST_ARGV="$test_tmp/argv"

applications="$HOME/.local/share/applications"

install_webapp() {
  bash "$ROOT/bin/omarchy-webapp-install" "$@" >/dev/null
}

desktop_value() {
  sed -n "s/^$2=//p" "$1" | head -1
}

# gio launch returns before the entry it spawned has run, so poll for the argv the
# stub records rather than reading the log once.
launched_argument() {
  local file="$1" attempt

  : >"$OMARCHY_TEST_ARGV"
  gio launch "$file" >/dev/null 2>&1 || return 1
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ -s $OMARCHY_TEST_ARGV ]] && break
    sleep 0.01
  done

  head -1 "$OMARCHY_TEST_ARGV"
}

# The Exec quoting escapes a dollar sign with a backslash, and the file syntax has
# to escape that backslash in turn. Left single, GLib reads \$ as an invalid escape
# and refuses the whole entry, so the web app vanishes from the launcher.
install_webapp 'Dollar App' 'https://example.com/a$b' someicon
dollar_file="$applications/Dollar App.desktop"

[[ -f $dollar_file ]] || fail "web app install writes a desktop entry"

[[ $(desktop_value "$dollar_file" Exec) == 'omarchy-launch-webapp "https://example.com/a\\$b"' ]] ||
  fail "Exec escapes the backslash its own quoting introduced" "$(desktop_value "$dollar_file" Exec)"
pass "Exec escapes the backslash its own quoting introduced"

[[ $(launched_argument "$dollar_file") == 'https://example.com/a$b' ]] ||
  fail "a URL containing a dollar sign reaches the browser unchanged"
pass "a URL containing a dollar sign reaches the browser unchanged"

# An unescaped % is read as a Desktop Entry field code and eaten, so ?q=a%20b used
# to arrive as ?q=a0b.
install_webapp 'Percent App' 'https://example.com/s?q=a%20b' someicon
percent_file="$applications/Percent App.desktop"

[[ $(launched_argument "$percent_file") == 'https://example.com/s?q=a%20b' ]] ||
  fail "a percent-encoded URL reaches the browser unchanged"
pass "a percent-encoded URL reaches the browser unchanged"

# A lone backslash is not a Desktop Entry escape sequence, so GLib cannot interpret
# a value that contains one.
install_webapp 'Back\slash App' 'https://example.com' someicon
backslash_file="$applications/Back\slash App.desktop"

[[ $(desktop_value "$backslash_file" Name) == 'Back\\slash App' ]] ||
  fail "a backslash in the app name is escaped" "$(desktop_value "$backslash_file" Name)"
pass "a backslash in the app name is escaped"

# The property the escaping exists for: a newline in a value must not be able to
# start a second key line.
inject_name=$(printf 'Inject\nExec=evil')
install_webapp "$inject_name" 'https://example.com' someicon
inject_file="$applications/$inject_name.desktop"

(( $(grep -c '^Exec=' "$inject_file") == 1 )) ||
  fail "a newline in the app name cannot inject a second Exec" "$(cat "$inject_file")"
pass "a newline in the app name cannot inject a second Exec"
