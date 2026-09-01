#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command desktop-file-validate
require_command gio

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
rom_dir="$test_tmp/roms"
applications="$test_home/.local/share/applications"
core_path="$test_tmp/fake-core.so"
mkdir -p "$mock_bin" "$test_home" "$rom_dir"
: >"$core_path"

for command in omarchy-notification-send update-desktop-database; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
exit 0
SH
done

cat >"$mock_bin/retroarch" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_ARGV"
SH

chmod +x "$mock_bin"/*

install_game() {
  HOME="$test_home" \
    PATH="$mock_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-games-retro-install" "$core_path" "$1"
}

malicious_rom="$rom_dir/Hostile"$'\n'"Exec=sh -c \"echo PWNED\".sfc"
: >"$malicious_rom"

if install_game "$malicious_rom" >"$test_tmp/malicious.out" 2>"$test_tmp/malicious.err"; then
  fail "retro install refuses a ROM path containing a control character"
fi
grep -Fqx 'Game and core paths cannot contain control characters.' "$test_tmp/malicious.err" ||
  fail "retro install explains why the ROM path was refused" "$(<"$test_tmp/malicious.err")"
[[ ! -e $applications ]] ||
  fail "retro install does not create a desktop entry for a hostile ROM name"
pass "retro install refuses a ROM path containing a control character"

safe_rom="$rom_dir/Game \"100%\" \\ Test.sfc"
: >"$safe_rom"
export OMARCHY_TEST_ARGV="$test_tmp/retroarch-args"
install_game "$safe_rom" >"$test_tmp/safe.out" 2>"$test_tmp/safe.err"

safe_desktop="$applications/game-100-test.desktop"
[[ -f $safe_desktop ]] ||
  fail "retro install creates a desktop entry for a normal ROM name"
desktop-file-validate "$safe_desktop" >"$test_tmp/validate.out" 2>"$test_tmp/validate.err" ||
  fail "retro install writes a valid desktop entry for special characters" "$(<"$test_tmp/validate.err")"
(( $(grep -c '^Exec=' "$safe_desktop") == 1 )) ||
  fail "retro install writes exactly one Exec key" "$(<"$safe_desktop")"
pass "retro install writes a valid desktop entry for special characters"

: >"$OMARCHY_TEST_ARGV"
HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" \
  gio launch "$safe_desktop" >"$test_tmp/gio.out" 2>"$test_tmp/gio.err" ||
  fail "the generated desktop entry launches through gio" "$(<"$test_tmp/gio.err")"

for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -s $OMARCHY_TEST_ARGV ]] && break
  sleep 0.01
done

grep -Fxq -- "$safe_rom" "$OMARCHY_TEST_ARGV" ||
  fail "desktop-entry escaping preserves a ROM path with quotes, percent, and backslash" "$(<"$OMARCHY_TEST_ARGV")"
pass "desktop-entry escaping preserves a ROM path with quotes, percent, and backslash"
