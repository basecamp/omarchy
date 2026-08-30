#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

export HOME="$test_tmp/home"
applications="$HOME/.local/share/applications"
mkdir -p "$applications"

# curl/file are unused when the icon is a plain name.
install_tui() {
  bash "$ROOT/bin/omarchy-tui-install" "$@" >/dev/null
}

desktop_value() {
  sed -n "s/^$2=//p" "$1" | head -1
}

# A slash in the name would write outside applications/ (e.g. into autostart).
if install_tui '../autostart/pwn' 'true' float someicon 2>"$test_tmp/slash.err"; then
  fail "tui install must refuse a name containing /"
fi
grep -F "App name cannot contain '/'" "$test_tmp/slash.err" >/dev/null ||
  fail "tui install explains a name containing /" "$(cat "$test_tmp/slash.err")"
pass "tui install refuses a name containing /"

# A newline in a value must not be able to start a second key line.
inject_name=$(printf 'Inject\nExec=evil')
install_tui "$inject_name" 'true' float someicon
inject_file="$applications/$inject_name.desktop"

(( $(grep -c '^Exec=' "$inject_file") == 1 )) ||
  fail "a newline in the app name cannot inject a second Exec" "$(cat "$inject_file")"
pass "a newline in the app name cannot inject a second Exec"

install_tui 'Quoted TUI' 'echo hi; id' float someicon
quoted_file="$applications/Quoted TUI.desktop"
exec_line=$(desktop_value "$quoted_file" Exec)

[[ $exec_line == *'"echo hi; id"'* ]] ||
  fail "Exec quotes the launch command as one argument" "$exec_line"
pass "Exec quotes the launch command as one argument"
