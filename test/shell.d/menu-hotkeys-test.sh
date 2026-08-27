#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# ---------------------------------------------------------------------------
# omarchy-menu-hotkeys turns the keybindings records into chip rows, with the
# records and the default-app resolvers stubbed so the test owns both sides.

stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

cat >"$stub_dir/omarchy-menu-keybindings" <<'STUB'
#!/bin/bash
if [[ $1 == "--records" ]]; then
  printf 'SUPER + K                           → Keybindings\texec\tomarchy-menu-keybindings\n'
  printf 'SUPER + RETURN                      → Terminal\texec\tomarchy-launch-terminal\n'
  printf 'SUPER ALT + RETURN                  → Tmux\texec\tomarchy-launch-terminal-tmux\n'
  printf 'SUPER + ESCAPE                      → System menu\texec\tomarchy-menu toggle system\n'
  printf 'SUPER + W / SUPER + Q               → Close window\texec\tomarchy-close-window\n'
  printf 'ALT + TAB                           → Reveal active window\tlua\thl.dsp.cyclenext()\n'
  printf 'SHIFT ALT + L                       → Copy URL\tsendshortcut\tSHIFT ALT,L,\n'
fi
STUB

cat >"$stub_dir/xdg-terminal-exec" <<'STUB'
#!/bin/bash
[[ ${1:-} == "--print-id" ]] && echo "Alacritty.desktop:/usr/share/xdg-terminals/Alacritty.desktop"
STUB

cat >"$stub_dir/xdg-settings" <<'STUB'
#!/bin/bash
echo "chromium.desktop"
STUB

chmod +x "$stub_dir/omarchy-menu-keybindings" "$stub_dir/xdg-terminal-exec" "$stub_dir/xdg-settings"

output=$(PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-menu-hotkeys")

assert_row() {
  local row="$1" description="$2"

  if grep -qxF "$row" <<<"$output"; then
    pass "$description"
  else
    fail "$description" "$output"
  fi
}

assert_row $'cmd\tomarchy-launch-terminal\tSUPER + RETURN' 'hotkeys report what each exec chord runs'
assert_row $'cmd\tomarchy-menu toggle system\tSUPER + ESCAPE' 'hotkeys report chords that open menu routes'
assert_row $'cmd\tomarchy-close-window\tSUPER + W' 'hotkeys keep only the chord that leads a merged row'
assert_row $'app\tAlacritty\tSUPER + RETURN' 'hotkeys resolve the terminal indirection to the default terminal app'

if grep -q $'^app\tchromium\t' <<<"$output"; then
  fail 'hotkeys skip the browser app row when no bind runs omarchy-launch-browser' "$output"
else
  pass 'hotkeys skip the browser app row when no bind runs omarchy-launch-browser'
fi

if grep -qE 'cyclenext|Copy URL' <<<"$output"; then
  fail 'hotkeys skip non-exec dispatchers' "$output"
else
  pass 'hotkeys skip non-exec dispatchers'
fi

if grep -qx $'app\tAlacritty\tSUPER ALT + RETURN' <<<"$output"; then
  fail 'hotkeys do not let a longer launcher command claim the terminal chord' "$output"
else
  pass 'hotkeys do not let a longer launcher command claim the terminal chord'
fi

# ---------------------------------------------------------------------------
# MenuModel matches the reported chords onto menu rows.

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')

assertEqual(
  menu.commandKey("  uwsm-app  --  obsidian %U "),
  'obsidian',
  'command keys shed launcher prefixes and Exec field codes'
)
assertEqual(
  menu.commandKey("omarchy-launch-webapp 'https://youtube.com/'"),
  menu.commandKey('omarchy-launch-webapp https://youtube.com'),
  'command keys compare webapp launches by URL regardless of quoting and trailing slash'
)
assertEqual(
  menu.commandKey("omarchy-launch-or-focus-webapp 'Google Messages' 'https://messages.google.com/web/conversations'"),
  menu.commandKey('omarchy-launch-webapp https://messages.google.com/web/conversations'),
  'command keys let the focus variant match the webapp desktop entry'
)

const rows = menu.parseHotkeyLines([
  'cmd\tomarchy-menu-keybindings\tSUPER + K',
  'cmd\tomarchy-menu toggle capture\tSUPER CTRL + C',
  'cmd\tomarchy-menu toggle system\tSUPER + ESCAPE',
  'cmd\tomarchy-menu toggle system\tXF86PowerOff',
  "cmd\tomarchy-launch-webapp 'https://youtube.com/'\tSUPER SHIFT + Y",
  'app\tAlacritty\tSUPER + RETURN',
  'garbage line',
  'cmd\tmissing-chord\t',
].join('\n'))

assertEqual(rows.length, 6, 'hotkey lines parse rows and drop malformed ones')

assertEqual(
  menu.compactChord('SUPER SHIFT CTRL + SPACE'),
  'SUP+SFT+CTL+SPC',
  'chips spell modifiers short and join them without padding'
)
assertEqual(
  menu.compactChord('SHIFT + XF86MonBrightnessDown'),
  'SFT+BRIDN',
  'chips name what a media key does rather than its X11 spelling'
)
assertEqual(
  menu.compactChord('SUPER + XF86Sleep'),
  'SUP+SLEEP',
  'an unnamed media key still sheds the vendor prefix'
)
assertEqual(menu.compactChord(''), '', 'an absent chord stays absent')

const sources = menu.mergeMenuSources(menu.parseMenuJsonc(`
{
  "learn": {"label":"Learn"},
  "learn.keybindings": {"label":"Keybindings","action":"omarchy-menu-keybindings"},
  "system": {"label":"System"},
  "system.lock": {"label":"Lock","action":"omarchy-system-lock","hotkey":"SUPER + L"},
  "trigger": {"label":"Trigger"},
  "trigger.capture": {"label":"Capture","aliases":["capture"]},
  "trigger.capture.screenshot": {"label":"Screenshot","action":"omarchy-capture-screenshot"},
}
`), [])

const withApps = menu.mergeAppRows(sources.items, sources.itemOrder, [
  { id: 'apps.Alacritty', parent: 'apps', kind: 'app', appId: 'Alacritty', label: 'Alacritty', exec: 'alacritty', aliases: [] },
  { id: 'apps.YouTube', parent: 'apps', kind: 'app', appId: 'YouTube', label: 'YouTube', exec: 'omarchy-launch-webapp https://youtube.com/', aliases: [] },
])

const hotkeys = menu.hotkeyIndex(withApps.items, withApps.itemOrder, rows)

assertEqual(hotkeys['learn.keybindings'], 'SUP+K', 'hotkey index matches a row by its action')
assertEqual(hotkeys['trigger.capture'], 'SUP+CTL+C', 'hotkey index resolves menu routes through aliases')
assertEqual(hotkeys['system'], 'SUP+ESC', 'hotkey index keeps the first chord that claims a route')
assertEqual(hotkeys['system.lock'], 'SUP+L', 'an explicit hotkey wins over anything derived, in the chip spelling')
assertEqual(hotkeys['apps.Alacritty'], 'SUP+RET', 'hotkey index matches app rows by desktop id')
assertEqual(hotkeys['apps.YouTube'], 'SUP+SFT+Y', 'hotkey index matches app rows by what their desktop entry runs')
assertEqual(hotkeys['trigger.capture.screenshot'], undefined, 'rows no chord reaches carry no chip')

assertEqual(
  menu.displayRow(withApps.items, withApps.itemOrder, {}, {}, hotkeys, withApps.items['learn.keybindings'], '', 0).hotkey,
  'SUP+K',
  'display rows carry their hotkey chip'
)

assert(
  /omarchy-menu-hotkeys/.test(menuQml),
  'menu shell derives hotkey chips from omarchy-menu-hotkeys'
)
assert(
  /required property string hotkey/.test(menuQml),
  'menu rows render their hotkey chip'
)
JS
