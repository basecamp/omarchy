#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const search = requireFromRoot('shell/services/AppSearch.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
const appLibraryQml = fs.readFileSync(path.join(root, 'shell/services/AppLibrary.qml'), 'utf8')

const entries = [
  {
    name: 'Google Contacts',
    genericName: 'Address Book',
    comment: 'Manage contacts',
    keywords: ['contacts', 'address book', 'people'],
    id: 'google-contacts.desktop'
  },
  {
    name: 'Calculator',
    genericName: 'Calculator',
    comment: 'Perform arithmetic, scientific or financial calculations',
    keywords: ['calculation', 'arithmetic', 'scientific', 'financial'],
    id: 'org.gnome.Calculator.desktop'
  },
  {
    name: 'OBS Studio',
    genericName: 'Streaming/Recording Software',
    comment: 'Free and Open Source Streaming/Recording Software',
    keywords: ['streaming', 'recording', 'capture'],
    id: 'com.obsproject.Studio.desktop'
  },
  {
    name: 'Aether',
    genericName: '',
    comment: 'Minimal internet radio player',
    keywords: ['audio', 'music', 'radio'],
    id: 'io.github.taqi.aether.desktop'
  },
  {
    name: 'Xournal++',
    genericName: 'Notetaking',
    comment: 'Take handwritten notes',
    keywords: ['notes', 'pdf', 'annotation'],
    id: 'com.github.xournalpp.xournalpp.desktop'
  },
  {
    name: 'RustDesk',
    genericName: 'Remote Desktop',
    comment: 'Remote desktop control',
    keywords: ['remote', 'desktop', 'control'],
    id: 'com.rustdesk.RustDesk.desktop'
  }
]

const contactMatches = search.sortedEntries(entries, 'contact').map(row => search.entryName(row.entry))
assertDeepEqual(contactMatches, ['Google Contacts'], 'contact search only returns direct contact matches')

assert(
  search.fuzzyScore(entries[1], 'contact') < 0,
  'calculator does not match contact as a loose subsequence'
)

const acronymMatches = search.sortedEntries(entries, 'gc').map(row => search.entryName(row.entry))
assertEqual(acronymMatches[0], 'Google Contacts', 'short acronym matching still works')

const directMatches = search.sortedEntries(entries, 'obs').map(row => search.entryName(row.entry))
assertEqual(directMatches[0], 'OBS Studio', 'direct app-name matching still works')

// The menu's Apps submenu is the launcher now: app rows launch and uninstall
// through the shared app library instead of running commands themselves.
const activateMatch = menuQml.match(/function activateIndex\(index, fromPointer\) \{([\s\S]*?)\n  \}/)
assert(activateMatch, 'menu activateIndex function exists')
assert(
  activateMatch[1].includes('root.appLibrary.launch('),
  'menu routes app launch through the shared app library'
)
assert(
  !activateMatch[1].includes('entry.execute()'),
  'menu does not execute desktop entries directly'
)

const confirmDeleteMatch = menuQml.match(/function confirmDelete\(\) \{([\s\S]*?)\n  \}/)
assert(confirmDeleteMatch, 'menu confirmDelete function exists')
assert(
  confirmDeleteMatch[1].includes('root.appLibrary.remove('),
  'menu delete routes through the shared app library'
)
assert(
  confirmDeleteMatch[1].includes('root.cancel()'),
  'menu delete closes the menu after confirmation'
)

assert(
  /function remove\(desktopId, name\) \{[\s\S]*?omarchy-remove-launcher-entry[\s\S]*?\n  \}/.test(appLibraryQml),
  'app library remove runs the remover through the shell'
)

assert(
  /function launch\(desktopId, name\) \{[\s\S]*?uwsm-app[\s\S]*?\n  \}/.test(appLibraryQml) &&
    appLibraryQml.includes('Util.execDetached("uwsm-app -- gtk-launch "'),
  'app library launches desktop entries through gtk-launch in their own scope'
)

assert(
  appLibraryQml.includes('Util.shellQuote(id + ".desktop")'),
  'app library launches by full file name so ids ending in .desktop (org.telegram.desktop) resolve'
)

assert(
  /function iconIndexScanCommand\(\)[\s\S]*-path "\*\/apps\/\*" -o -path "\*\/devices\/\*"/.test(appLibraryQml),
  'app library fallback icon index includes device icons'
)

assert(
  appLibraryQml.includes('command: ["bash", "-c", root.hiddenEntryScanCommand()]') &&
    appLibraryQml.includes('command: ["bash", "-c", root.iconIndexScanCommand()]') &&
    !appLibraryQml.includes('"-lc"'),
  'app library scans avoid login shells whose profile activation retriggers the desktop-entry watcher'
)

assert(
  /if \(active === "apps"\) \{[\s\S]*?rows\.sort\(function\(a, b\)/.test(menuQml),
  'apps menu enforces alphabetical display order after provider refreshes'
)

const iconSourceMatch = appLibraryQml.match(/function iconSource\(icon\) \{([\s\S]*?)\n  \}/)
assert(iconSourceMatch, 'app library iconSource function exists')
assert(
  iconSourceMatch[1].indexOf('root.iconIndex[value]') < iconSourceMatch[1].indexOf('Quickshell.iconPath(value, true)'),
  'app library prefers indexed app icons over ambiguous themed icons'
)

const beginLaunchMatch = appLibraryQml.match(/function beginLaunchFeedback\(name\) \{([\s\S]*?)\n  \}/)
assert(beginLaunchMatch, 'app library beginLaunchFeedback function exists')
assert(
  !beginLaunchMatch[1].includes('root.launchOsdOpen = false'),
  'app library keeps owning an OSD a previous launch left on screen'
)

const openMatch = menuQml.match(/function openExistingMenu\(initialMenu\) \{([\s\S]*?)\n  \}/)
assert(openMatch, 'menu openExistingMenu function exists')
assert(
  openMatch[1].includes('root.appLibrary.refreshIcons()'),
  'menu refreshes the shared icon index when opened'
)
JS



# The scan decides which file wins a basename, and iconSource() consults the
# index before the themed lookup, so scan precedence is what picks the icon.
# Run the command the QML actually ships against a fixture theme tree.
require_command node

scan_command=$(node -e '
const fs = require("fs")
const qml = fs.readFileSync(process.env.ROOT + "/shell/services/AppLibrary.qml", "utf8")
const body = qml.match(/function iconIndexScanCommand\(\) \{([\s\S]*?)\n  \}/)
if (!body) { console.error("iconIndexScanCommand not found"); process.exit(1) }
process.stdout.write(new Function(body[1])())
')

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

icons=$tmpdir/.local/share/icons
home_icons=$tmpdir/.icons
xdg_icons=$tmpdir/xdg/icons
mkdir -p \
  "$icons/OmaSelected/scalable/apps" "$icons/OmaSelected/16x16/apps" \
  "$icons/OmaSelected/48x48/apps" "$icons/OmaSelected/symbolic/apps" \
  "$icons/OmaParentA/scalable/apps" "$icons/OmaParentB/scalable/apps" \
  "$icons/OmaGrandparent/scalable/apps" "$icons/OmaUnrelated/scalable/apps" \
  "$icons/OmaNear/scalable/apps" "$icons/OmaFar/scalable/apps" \
  "$icons/hicolor/scalable/apps" \
  "$home_icons/OmaSplit" "$xdg_icons/OmaSplit/scalable/apps"

# OmaParentA lists hicolor before a real parent, and OmaGrandparent inherits
# back to the active theme: both shapes occur in shipped themes.
printf '[Icon Theme]\nInherits=OmaParentA,OmaParentB,OmaSplit\n' > "$icons/OmaSelected/index.theme"
printf '[Icon Theme]\nInherits=hicolor,OmaGrandparent\n' > "$icons/OmaParentA/index.theme"
printf '[Icon Theme]\nInherits=OmaSelected\n'            > "$icons/OmaGrandparent/index.theme"

# OmaSplit is defined twice. Only the copy in the earlier base directory
# defines it, so OmaFar must never enter the search graph.
printf '[Icon Theme]\nInherits=OmaNear\n' > "$home_icons/OmaSplit/index.theme"
printf '[Icon Theme]\nInherits=OmaFar\n'  > "$xdg_icons/OmaSplit/index.theme"

touch \
  "$icons/OmaSelected/scalable/apps/oma-test-selected.svg" \
  "$icons/OmaParentA/scalable/apps/oma-test-selected.svg" \
  "$icons/OmaParentA/scalable/apps/oma-test-inherited.svg" \
  "$icons/hicolor/scalable/apps/oma-test-inherited.svg" \
  "$icons/OmaGrandparent/scalable/apps/oma-test-depth.svg" \
  "$icons/OmaParentB/scalable/apps/oma-test-depth.svg" \
  "$icons/OmaGrandparent/scalable/apps/oma-test-distant.svg" \
  "$icons/hicolor/scalable/apps/oma-test-distant.svg" \
  "$icons/hicolor/scalable/apps/oma-test-shipped.svg" \
  "$icons/OmaUnrelated/scalable/apps/oma-test-unselected.svg" \
  "$icons/OmaSelected/16x16/apps/oma-test-sized.svg" \
  "$icons/OmaSelected/scalable/apps/oma-test-sized.svg" \
  "$icons/OmaSelected/symbolic/apps/oma-test-mono.svg" \
  "$icons/OmaSelected/48x48/apps/oma-test-mono.svg" \
  "$icons/OmaNear/scalable/apps/oma-test-near.svg" \
  "$icons/OmaFar/scalable/apps/oma-test-far.svg" \
  "$icons/OmaSelected/48x48/apps/oma-test-format.png" \
  "$icons/OmaParentA/scalable/apps/oma-test-format.svg"

mkdir -p "$tmpdir/bin"
printf '#!/bin/bash\necho "%s"\n' "'OmaSelected'" > "$tmpdir/bin/gsettings"
chmod +x "$tmpdir/bin/gsettings"

# An inheritance cycle would hang the walk rather than fail an assertion.
run_scan() {
  timeout 30 env -i HOME="$tmpdir" XDG_DATA_DIRS="$tmpdir/xdg" PATH="$tmpdir/bin:$PATH" \
    bash -c "$scan_command"
}

run_scan > "$tmpdir/scan" || fail "icon index scan terminates on a theme inheritance cycle"
pass "icon index scan terminates on a theme inheritance cycle"

# What indexIconLine() keeps: the first path whose basename matches.
indexed() {
  awk -F/ -v want="$1" '{ name = $NF; sub(/\.[^.]*$/, "", name); if (name == want) { print; exit } }' "$tmpdir/scan"
}

expect_theme() {
  local name=$1 theme=$2 description=$3
  [[ $(indexed "$name") == *"/$theme/"* ]] || fail "$description" "$(indexed "$name")"
  pass "$description"
}

expect_theme oma-test-selected OmaSelected "icon index prefers the active theme over the themes it inherits"
expect_theme oma-test-inherited OmaParentA "icon index prefers an inherited theme over hicolor"
expect_theme oma-test-depth OmaGrandparent "icon index exhausts a parent's own inheritance before the next declared parent"
expect_theme oma-test-distant OmaGrandparent "icon index searches hicolor last even when a theme inherits it first"
expect_theme oma-test-near OmaNear "icon index takes a theme's inheritance from the first index.theme in base order"
expect_theme oma-test-format OmaSelected "icon index exhausts a theme before the next one, whatever formats they carry"
expect_theme oma-test-shipped hicolor "icon index still covers icons an app ships under hicolor"
expect_theme oma-test-sized scalable "icon index prefers scalable over a fixed-size directory"
expect_theme oma-test-mono 48x48 "icon index never resolves an app name to a symbolic glyph"

[[ -z $(indexed oma-test-far) ]] ||
  fail "icon index ignores an Inherits shadowed by an earlier base directory" "$(indexed oma-test-far)"
pass "icon index ignores an Inherits shadowed by an earlier base directory"

[[ -z $(indexed oma-test-unselected) ]] ||
  fail "icon index leaves names only an uninherited theme provides to the themed lookup" "$(indexed oma-test-unselected)"
pass "icon index leaves names only an uninherited theme provides to the themed lookup"

run_scan > "$tmpdir/scan-again"
diff -q "$tmpdir/scan" "$tmpdir/scan-again" >/dev/null ||
  fail "icon index scan returns the same order every run"
pass "icon index scan returns the same order every run"
