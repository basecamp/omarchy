#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
stub_bin="$test_tmp/bin"
mkdir -p "$test_home" "$stub_bin"

for stub in omarchy-notification-send update-desktop-database; do
  printf '#!/bin/bash\n:\n' >"$stub_bin/$stub"
  chmod +x "$stub_bin/$stub"
done

core="$test_tmp/mgba_libretro.so"
printf 'core\n' >"$core"

run_install() {
  HOME="$test_home" PATH="$stub_bin:/usr/bin" \
    "$ROOT/bin/omarchy-games-retro-install" "$core" "$1"
}

# A newline in a game file name used to become a new key line in the launcher
# entry. A name like this one would add a key of its own to the file.
game="$test_tmp/"$'pwn\nX-Omarchy-Hole=injected.sfc'
printf 'rom\n' >"$game"

run_install "$game" >/dev/null 2>&1 || true

desktop_file="$test_home/.local/share/applications/pwn-x-omarchy-hole-injected.desktop"
[[ -f $desktop_file ]] || fail "retro-install writes a desktop entry for the game"

if grep -q '^X-Omarchy-Hole=' "$desktop_file"; then
  fail "retro-install keeps a newline in a name from adding a key line"
fi
grep -qF 'Name=Pwn\nX-Omarchy-Hole=injected' "$desktop_file" ||
  fail "retro-install keeps a name with a newline on one escaped line"
grep -q "^Exec=retroarch -L " "$desktop_file" ||
  fail "retro-install keeps the Exec line whole when the path holds a newline"
pass "retro-install escapes a newline in a game name instead of adding a key line"

# A double quote in a file name used to step outside its quoted Exec argument.
game="$test_tmp/"$'qu"ote.sfc'
printf 'rom\n' >"$game"

run_install "$game" >/dev/null 2>&1 || true

desktop_file="$test_home/.local/share/applications/qu-ote.desktop"
[[ -f $desktop_file ]] || fail "retro-install writes a desktop entry for the game"
grep '^Exec=' "$desktop_file" | grep -qF 'qu\\"ote.sfc"' ||
  fail "retro-install escapes a double quote in a game path on the Exec line"
pass "retro-install keeps a double quote inside its Exec argument"

# A plain game keeps the same entry this command always wrote.
game="$test_tmp/Zelda.sfc"
printf 'rom\n' >"$game"

run_install "$game" >/dev/null 2>&1 || true

desktop_file="$test_home/.local/share/applications/zelda.desktop"
[[ -f $desktop_file ]] || fail "retro-install writes a desktop entry for a plain game"
grep -qF 'Name=Zelda' "$desktop_file" ||
  fail "retro-install writes the plain name"
grep -qF "Exec=retroarch -L \"$core\" \"$game\"" "$desktop_file" ||
  fail "retro-install writes the same Exec line as before for plain paths"
pass "retro-install writes the same entry as before for a plain game"
