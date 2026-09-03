#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

vm="$ROOT/bin/omarchy-windows-vm"
[[ -f $vm ]] || fail "omarchy-windows-vm is present"

# Source must clear setgid after chmod 0700 (#9943).
grep -F 'chmod g-s' "$vm" >/dev/null ||
  fail "windows-vm clears setgid after normalizing mount modes"
grep -F 'unexpected mode' "$vm" >/dev/null ||
  fail "windows-vm reports unexpected mount modes instead of silent return"
pass "windows-vm clears setgid and reports mode failures"

# Reproduce GNU chmod retaining setgid, then the fix sequence.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
dir="$test_tmp/Windows"
mkdir -p "$dir"
chmod 2777 "$dir"
[[ $(stat -c '%a' "$dir") == 2777 ]] || fail "fixture starts setgid+world"
chmod 0700 "$dir"
[[ $(stat -c '%a' "$dir") == 2700 ]] ||
  fail "GNU chmod 0700 retains setgid as 2700" "$(stat -c '%a' "$dir")"
pass "reproduced: chmod 0700 leaves setgid as 2700"

chmod g-s,o-t -- "$dir"
[[ $(stat -c '%a' "$dir") == 700 ]] ||
  fail "chmod g-s,o-t clears setgid to 700" "$(stat -c '%a' "$dir")"
pass "chmod g-s,o-t normalizes container 2777 down to 700"

# Extract and run the prepare_user_mount_sources chmod pair against a fixture.
# Full prepare_caller_mounts needs root/bind mounts; the user-path sequence is
# the same fix and is what every launch hits on ~/Windows.
mkdir -p "$test_tmp/home/.windows" "$test_tmp/home/Windows"
chmod 2777 "$test_tmp/home/Windows"
chmod 2777 "$test_tmp/home/.windows"
HOME="$test_tmp/home" bash -c '
  storage="$HOME/.windows"
  shared="$HOME/Windows"
  chmod 0700 -- "$storage" "$shared" || exit 1
  chmod g-s,o-t -- "$storage" "$shared" 2>/dev/null || true
  s=$(stat -c "%a" "$storage")
  w=$(stat -c "%a" "$shared")
  [[ $s == 700 && $w == 700 ]]
' || fail "user mount normalize reaches mode 700 from 2777"
pass "user mount normalize reaches mode 700 from 2777"
