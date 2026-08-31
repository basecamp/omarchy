#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The icon index keeps the first path it sees for a name, so what the launcher
# draws is decided by the order the scan emits paths in. These run the command
# AppLibrary builds, against a tree holding the same icon in three themes.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
icons="$test_tmp/share/icons"
home="$test_tmp/home"
mkdir -p "$mock_bin" "$home/.icons" "$home/.local/share/icons"

printf '#!/bin/bash\nprintf "%%s\\n" "'"'"'${OMARCHY_TEST_ICON_THEME:-Chosen}'"'"'"\n' >"$mock_bin/gsettings"
chmod +x "$mock_bin/gsettings"

icon() { mkdir -p "$(dirname "$1")"; : >"$1"; }

# The chosen theme keeps its large sizes behind symlinks, the way Papirus does.
icon "$icons/Chosen/64x64/apps/browser.svg"
mkdir -p "$icons/Chosen/128x128"
ln -s ../64x64/apps "$icons/Chosen/128x128/apps"
icon "$icons/Chosen/scalable/devices/printer.svg"

# A theme nobody selected, in the root that is searched first.
icon "$home/.local/share/icons/Unselected/scalable/apps/browser.svg"
icon "$home/.local/share/icons/Unselected/scalable/apps/only-here.svg"

# An application shipping its own icon.
icon "$icons/hicolor/256x256/apps/self-installed.png"

# Pull the command out of the shell source so the test exercises what ships.
scan_command=$(
  python3 - "$ROOT/shell/services/AppLibrary.qml" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
block = src[src.index('function iconIndexScanCommand'):]
block = block[block.index('return ['):block.index("].join(' ')")]
parts = re.findall(r"^\s*'((?:[^'\\]|\\.)*)',?\s*$", block, re.M)
print(' '.join(p.replace("\\'", "'").replace('\\\\', '\\') for p in parts))
PY
)

run_scan() {
  HOME="$home" XDG_DATA_DIRS="$test_tmp/share" PATH="$mock_bin:$PATH" \
    OMARCHY_TEST_ICON_THEME="${1:-Chosen}" bash -c "$scan_command" 2>/dev/null
}

# Run it once; every check below reads the same output.
scan_out="$test_tmp/scan"
run_scan >"$scan_out"

# Same rule as AppLibrary's parser: the first path seen for a name wins.
resolve() {
  awk -v want="$1" -F/ '{
    base = $NF
    sub(/\.[^.]*$/, "", base)
    if (base == want) { print; found = 1; exit }
  } END { if (!found) print "<unresolved>" }' "$scan_out"
}

got=$(resolve browser)
[[ $got == "$icons/Chosen/"* ]] ||
  fail "the configured icon theme wins over a theme that is merely present" "$got"
pass "the configured icon theme wins over a theme that is merely present"

got=$(resolve only-here)
[[ $got == "$home/.local/share/icons/Unselected/"* ]] ||
  fail "an icon no chosen theme carries is still found" "$got"
pass "an icon no chosen theme carries is still found"

got=$(resolve self-installed)
[[ $got == "$icons/hicolor/"* ]] ||
  fail "an application's own hicolor icon is found" "$got"
pass "an application's own hicolor icon is found"

# 128x128/apps is a symlink; find needs -L to descend into it at all.
grep -q "Chosen/128x128/apps/browser.svg" "$scan_out" ||
  fail "symlinked size directories inside a theme are searched" "$(grep Chosen "$scan_out" | head -3)"
pass "symlinked size directories inside a theme are searched"

# Within the theme, the larger artwork is emitted before the smaller one.
order=$(grep -n "Chosen/\(128x128\|64x64\)/apps/browser.svg" "$scan_out" | head -2)
[[ $(head -1 <<<"$order") == *"128x128"* ]] ||
  fail "the largest artwork in a theme is preferred" "$order"
pass "the largest artwork in a theme is preferred"

got=$(resolve printer)
[[ $got == *"/devices/"* ]] ||
  fail "device icons are still indexed" "$got"
pass "device icons are still indexed"
