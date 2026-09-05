#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
const defaultMenuJsonc = fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')

const parsed = menu.parseMenuJsonc(`
{
  // comment
  "items": {
    "root": { "label": "Go" },
    "style": { "label": "Style" },
    "style.theme": {
      "label": "Themes",
      "aliases": "theme",
      "description": "appearance colors",
      "action": "omarchy-theme-set"
    },
  },
}
`)

assertEqual(parsed.length, 3, 'menu parses JSONC with comments and trailing commas')
assertDeepEqual(
  parsed.find(item => item.id === 'style.theme'),
  {
    id: 'style.theme',
    parent: 'style',
    kind: 'action',
    icon: '',
    iconFont: '',
    label: 'Themes',
    title: '',
    target: '',
    description: 'appearance colors',
    action: 'omarchy-theme-set',
    provider: '',
    aliases: ['theme'],
    when: '',
    checked: '',
    disabled: ''
  },
  'menu normalizes parsed items'
)

const user = [
  menu.normalizeItem('style.theme', { label: 'Theme picker', aliases: ['theme', 'colors'], action: 'custom-theme' }),
  menu.normalizeItem('tools', { label: 'Tools' })
]
const merged = menu.mergeMenuSources(parsed, user)
assertEqual(merged.items['style.theme'].label, 'Theme picker', 'menu user entries override default entries')
assertEqual(merged.items['style.theme'].order, 2, 'menu preserves original order on override')
assert(merged.items.root, 'menu injects root when merging sources')

assertEqual(menu.slugify('Power Saver!'), 'power-saver', 'menu slugifies provider rows')
assertEqual(menu.pathFor(merged.items, 'style.theme'), 'Style › Theme picker', 'menu builds item paths')
assertEqual(menu.parentPathFor(merged.items, 'style.theme'), 'Style', 'menu builds parent paths')
assert(menu.isDescendantOf(merged.items, 'style.theme', 'style'), 'menu detects descendants')
assertEqual(menu.childCount(merged.items, merged.itemOrder, 'style'), 1, 'menu counts children')
assertEqual(menu.labelFor({ id: 'style.theme', label: 'Theme', checked: 'cmd' }, { 'style.theme': true }), 'Theme ✓', 'menu appends checked marker')
assertEqual(menu.labelFor({ id: 'install.browser.zen', label: 'Zen', disabled: 'cmd' }, {}, { 'install.browser.zen': true }), 'Zen ✓', 'menu marks a disabled row as something you already have')
assertEqual(menu.labelFor({ id: 'install.browser.zen', label: 'Zen', disabled: 'cmd' }, {}, { 'install.browser.zen': false }), 'Zen', 'menu leaves an uninstalled row unmarked')

const visibilityItems = {
  hardware: menu.normalizeItem('hardware', { label: 'Hardware' }),
  laptop: menu.normalizeItem('hardware.laptop', { label: 'Laptop', when: 'is-laptop', action: 'toggle-laptop' }),
  nested: menu.normalizeItem('nested', { label: 'Nested' }),
  branch: menu.normalizeItem('nested.branch', { label: 'Branch' }),
  leaf: menu.normalizeItem('nested.branch.leaf', { label: 'Leaf', when: 'has-leaf', action: 'run-leaf' }),
  dynamic: menu.normalizeItem('dynamic', { label: 'Dynamic', provider: 'items' })
}
const visibilityOrder = Object.keys(visibilityItems)
assert(!menu.isVisible(visibilityItems, visibilityOrder, { 'hardware.laptop': false }, visibilityItems.hardware), 'menu hides a submenu with no visible children')
assert(menu.isVisible(visibilityItems, visibilityOrder, { 'hardware.laptop': true }, visibilityItems.hardware), 'menu shows a submenu with a visible child')
assert(!menu.isVisible(visibilityItems, visibilityOrder, { 'nested.branch.leaf': false }, visibilityItems.nested), 'menu hides recursively empty submenus')
assert(menu.isVisible(visibilityItems, visibilityOrder, {}, visibilityItems.dynamic), 'menu keeps provider-backed submenus visible')

// `disabled:` is the softer guard: the row stays listed and only loses the
// cursor, which is how an already-installed app keeps its place in Install.
const installed = menu.normalizeItem('install.browser.zen', { label: 'Zen', disabled: 'omarchy-pkg-present zen-browser-bin', action: 'install-zen' })
assert(menu.isVisible({ 'install.browser.zen': installed }, ['install.browser.zen'], { 'install.browser.zen': false }, installed), 'menu keeps a disabled row visible')
assert(menu.isDisabled({ 'install.browser.zen': true }, installed), 'menu disables a row whose disabled: succeeded')
assert(!menu.isDisabled({ 'install.browser.zen': false }, installed), 'menu leaves a row selectable when its disabled: failed')
assert(!menu.isDisabled({ 'install.browser.zen': true }, visibilityItems.laptop), 'menu never disables a row that declares no disabled:')
assert(
  menu.displayRow({ 'install.browser.zen': installed }, ['install.browser.zen'], {}, { 'install.browser.zen': true }, installed, '', 0).disabled,
  'menu display rows carry their disabled state'
)
assert(
  /function matchesQuery\(entry, query\) \{\s*\n\s*return MenuModel\.matchesQuery\(entry, query, root\.isVisible\(entry\) && !root\.isDisabled\(entry\)\)/.test(menuQml),
  'menu search skips disabled rows, which belong to the submenu they sit in rather than a list of what you can do'
)

const entry = merged.items['style.theme']
assert(menu.matchesQuery(entry, 'theme', true), 'menu matches labels and aliases')
assert(menu.matchesQuery(entry, 'colors', true), 'menu matches aliases')
assert(!menu.matchesQuery(entry, 'missing', true), 'menu rejects missing terms')
assert(!menu.matchesQuery(entry, 'theme', false), 'menu hides invisible matches')
assert(menu.searchScore(merged.items, entry, 'theme') < menu.searchScore(merged.items, entry, 'appearance'), 'menu scores name matches above description matches')

assertDeepEqual(
  menu.displayRow(merged.items, merged.itemOrder, {}, {}, entry, 'Style', 12, 'search'),
  {
    itemId: 'style.theme',
    disabled: false,
    kind: 'action',
    icon: '',
    iconFont: '',
    appIcon: '',
    appId: '',
    label: 'Theme picker',
    target: 'style.theme',
    detail: 'Style',
    path: 'Style › Theme picker',
    childCount: 0,
    action: 'custom-theme',
    provider: '',
    score: 12,
    section: 'search'
  },
  'menu builds display rows'
)

const defaultItems = menu.parseMenuJsonc(defaultMenuJsonc)
const defaultById = Object.fromEntries(defaultItems.map(item => [item.id, item]))

// Needs the real menu: app rows sort after all menu items, and only at that
// item count does the order tiebreak alone bury an installed app.
const rankBase = menu.mergeMenuSources(defaultItems, [])
const ranked = menu.mergeAppRows(rankBase.items, rankBase.itemOrder, [
  { id: 'apps.brave', parent: 'apps', kind: 'app', label: 'Brave', description: '', aliases: [] },
  { id: 'apps.fontforge', parent: 'apps', kind: 'app', label: 'FontForge', description: '', aliases: [] },
  { id: 'apps.zen', parent: 'apps', kind: 'app', label: 'Zen Browser', description: '', aliases: [] }
])
const rankScore = (id, query) => menu.searchScore(ranked.items, ranked.items[id], query)
assert(
  ['install.browser.brave', 'remove.browser.brave', 'setup.default.browser.brave'].every(
    id => rankScore('apps.brave', 'brave') < rankScore(id, 'brave')
  ),
  'menu ranks an installed app above menu entries matching the query equally well'
)
assert(
  ['install.browser.zen', 'remove.browser.zen', 'setup.default.browser.zen'].every(
    id => rankScore('apps.zen', 'zen') < rankScore(id, 'zen')
  ),
  'menu ranks an app matching the query as a whole word above exact-labeled menu entries'
)
assert(
  rankScore('style.font', 'font') < rankScore('apps.fontforge', 'font'),
  'menu keeps a better-matching menu entry above a weaker app match'
)

// Routing: htop ships `Keywords=system;...`, which app rows carry as aliases.
// An installed app must never capture a menu route (SUPER+ESCAPE opens the
// `system` menu), while its keywords keep working for search.
const routed = menu.mergeAppRows(rankBase.items, rankBase.itemOrder, [
  { id: 'apps.htop', parent: 'apps', kind: 'app', label: 'Htop', description: 'Process Viewer', aliases: ['Process Viewer', 'system', 'process'] }
])
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, 'system'), 'system', 'menu routes an exact id even when an app keyword matches it')
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, 'process'), 'process', 'menu never routes to an app row through its keywords')
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, 'power-menu'), 'system', 'menu routes declared aliases to their item')
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, 'power_menu'), 'system', 'menu normalizes underscores in routes')
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, ''), 'root', 'menu routes empty input to root')
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, 'no-such-route'), 'no-such-route', 'menu falls through to the literal input')
assert(menu.matchesQuery(routed.items['apps.htop'], 'system', true), 'menu still finds an app by its keywords in search')
assert(
  /function resolveRoute\(input\) \{\s*\n\s*return MenuModel\.resolveRoute\(root\.items, root\.itemOrder, input\)\s*\n\s*\}/.test(menuQml),
  'menu delegates route resolution to the shared model'
)
const triggerItems = defaultItems.filter(item => item.parent === 'trigger')
assertEqual(
  triggerItems[0].id,
  'trigger.emoji',
  'menu lists Emoji first under Trigger'
)
assertEqual(
  defaultById['trigger.emoji'].action,
  'omarchy-menu-emoji',
  'menu opens the emoji picker from Trigger'
)
assert(
  defaultById['update.omarchy'].icon === '\ue900',
  'menu update Omarchy entry uses the Omarchy glyph'
)
assert(
  defaultById['update.omarchy'].iconFont === 'omarchy',
  'menu update Omarchy entry renders the private glyph with the Omarchy font'
)
assertEqual(
  defaultById['update.themes'].when,
  'omarchy-theme-extras',
  'menu hides Extra Themes until a theme cloned from git is there to update'
)
assert(
  defaultById['setup.input'].action.includes('input.lua'),
  'menu keeps Input as a direct config action'
)
assert(
  defaultById['setup.direct-boot'].action.includes('omarchy-setup-direct-boot'),
  'menu places Direct Boot directly under Setup'
)
assert(
  defaultById['setup.reset'].action.includes('omarchy-system-factory-reset'),
  'menu exposes Reset Computer under Setup'
)
const setupEntries = defaultItems.filter(item => item.parent === 'setup')
assertEqual(
  setupEntries[setupEntries.length - 1].id,
  'setup.reset',
  'menu lists Reset Computer last under Setup'
)
const expectedAgents = {
  agy: { icon: '󰫢', label: 'Antigravity' },
  pi: { icon: '\ue901', iconFont: 'omarchy', label: 'Pi' },
  omp: { icon: '\ue903', iconFont: 'omarchy', label: 'omp' },
  opencode: { icon: '\ue902', iconFont: 'omarchy', label: 'OpenCode' },
  ori: { icon: '\ue909', iconFont: 'omarchy', label: 'Ori' },
  claude: { icon: '󰛄', label: 'Claude' },
  codex: { icon: '\ue905', iconFont: 'omarchy', label: 'Codex' },
  grok: { icon: '\ue904', iconFont: 'omarchy', label: 'Grok' },
  hermes: { icon: '\ue90a', iconFont: 'omarchy', label: 'Hermes' },
  copilot: { icon: '', label: 'Copilot' },
  crush: { icon: '󰋑', label: 'Crush' },
}
assert(
  Object.entries(expectedAgents).every(([agent, expected]) => {
    const entry = defaultById[`setup.default.agent.${agent}`]
    return entry
      && entry.icon === expected.icon
      && entry.iconFont === (expected.iconFont || '')
      && entry.label === expected.label
      && entry.action === `omarchy-default-agent ${agent}`
      && !entry.when
      && entry.checked.includes(`== \"${agent}\"`)
  }),
  'menu exposes every mise-installable coding agent with its own glyph under Defaults > Agent'
)
assertDeepEqual(
  defaultItems
    .filter(item => item.parent === 'setup.default.agent')
    .map(item => item.label),
  ['Antigravity', 'Claude', 'Codex', 'Copilot', 'Crush', 'Grok', 'Hermes', 'omp', 'OpenCode', 'Ori', 'Pi'],
  'menu sorts coding agents alphabetically'
)
const expectedDefaults = {
  browser: ['Chromium', 'Chrome', 'Brave', 'Brave Origin', 'Edge', 'Firefox', 'Zen'],
  terminal: ['Alacritty', 'Foot', 'Ghostty', 'Kitty'],
  editor: ['Neovim', 'VSCode', 'Cursor', 'Zed', 'Sublime Text', 'Helix', 'Vim', 'Emacs']
}
assert(
  Object.entries(expectedDefaults).every(([type, labels]) => {
    const entries = defaultItems.filter(item => item.parent === `setup.default.${type}`)
    return entries.map(item => item.label).join('\0') === labels.join('\0')
      && entries.every(item => !item.when)
  }),
  'menu always exposes every supported browser, terminal, and editor under Defaults'
)
assert(!defaultById['install.ai.crush'], 'menu removes Crush from Install > AI')
// Software you already have keeps its place in Install, dimmed rather than
// dropped, so the list reads as a catalog of what Omarchy can install.
// Chromium Account is the sole Install row with anything left to hide for, so
// any other `when:` here is a row that went back to vanishing once installed.
assertDeepEqual(
  defaultItems
    .filter(item => item.id.startsWith('install.') && item.action && item.when)
    .map(item => item.id),
  ['install.service.chromium-account'],
  'menu never hides an Install row because the software is already there'
)
assert(
  ['install.browser.zen', 'install.editor.vscode', 'install.gaming.steam', 'install.development.rust', 'install.windows'].every(
    id => defaultById[id].disabled && !defaultById[id].when
  ),
  'menu dims the Install rows for software that is already installed'
)
assertEqual(
  defaultById['install.browser.zen'].disabled,
  'omarchy-pkg-present zen-browser-bin',
  'menu asks the same presence question it used to hide the row with'
)
// A guard can still be about something other than having the software: no
// Chromium at all means no account to wire up, and that row stays hidden.
assert(
  defaultById['install.service.chromium-account'].when === '[[ -f ~/.config/chromium-flags.conf ]]'
    && defaultById['install.service.chromium-account'].disabled.includes('oauth2-client-id'),
  'menu keeps hiding Chromium Account without Chromium, and dims it once the account is set up'
)
assert(
  defaultItems.filter(item => item.id.startsWith('remove.')).every(item => !item.disabled)
    && defaultById['remove.browser.zen'].when === 'omarchy-pkg-present zen-browser-bin',
  'menu still hides Remove rows for software that is not installed'
)
assertDeepEqual(
  defaultItems
    .filter(item => item.parent === 'remove')
    .map(item => item.id),
  [
    'remove.package',
    'remove.ai',
    'remove.service',
    'remove.development',
    'remove.theme',
    'remove.gaming',
    'remove.browser',
    'remove.webapp',
    'remove.tui',
    'remove.windows',
    'remove.preinstalls',
    'remove.security'
  ],
  'menu orders Remove categories like their Install counterparts, followed by Remove-only categories'
)
assert(
  defaultById['setup.security.passwordless-sudo'].action.includes('omarchy-sudo-passwordless'),
  'menu places Passwordless Sudo under Setup > Security'
)
assert(
  !defaultById['trigger.toggle.direct-boot'] && !defaultById['trigger.toggle.passwordless-sudo'],
  'menu removes the relocated toggles from Trigger > Toggle'
)
assert(
  defaultById['style.bar.position'].kind === 'menu',
  'menu groups Menu Bar positions in a submenu'
)
assert(
  ['top', 'bottom', 'left', 'right'].every(position => defaultById[`style.bar.position.${position}`].action === `omarchy-bar position ${position}`),
  'menu lists all Menu Bar positions under Position'
)
assertEqual(
  defaultById['style.bar.transparency'].action,
  'omarchy-bar transparent toggle',
  'menu exposes Menu Bar transparency as a toggle'
)
assertDeepEqual(
  defaultItems.filter(item => item.parent === 'setup.plugin').map(item => item.label),
  ['Enable Plugin', 'Disable Plugin', 'Add Plugin', 'Clone Plugin', 'Remove Plugin'],
  'menu manages plugins from Setup > Plugins'
)
assert(
  ['enable', 'disable', 'clone', 'remove'].every(
    verb => defaultById[`setup.plugin.${verb}`].action === `omarchy-menu-plugin ${verb}`
  ),
  'menu picks a plugin the way it already picks a theme or a timezone'
)
assert(
  !defaultById['setup.plugin.enable'].when && !defaultById['setup.plugin.disable'].when,
  'menu always offers Enable and Disable, which cover the built-in plugins too'
)
assert(
  defaultById['setup.plugin.remove'].when.includes('.config/omarchy/plugins'),
  'menu hides Remove until a plugin the user installed exists to delete'
)
assert(
  defaultById['setup.plugin.add'].action.includes('omarchy-plugin-add'),
  'menu adds a plugin through the CLI, where the trust warning and clone output are visible'
)

const pluginPicker = fs.readFileSync(path.join(root, 'bin/omarchy-menu-plugin'), 'utf8')
assert(
  /enable\).*\(\.enabled \| not\)/.test(pluginPicker) && /disable\).*\.canDisable and \.enabled/.test(pluginPicker),
  'plugin picker offers what each verb can act on'
)
assert(
  /remove\).*\(\.firstParty \| not\)/.test(pluginPicker)
    && /clone\).*\.firstParty/.test(pluginPicker)
    && !/kinds|bar-widget|A_BAR_OPTION|NOT_A_BAR_OPTION|BAR_ICON/.test(pluginPicker),
  'plugin picker leaves plugin-kind decisions to its data and the plugin command'
)

const pluginAdd = fs.readFileSync(path.join(root, 'bin/omarchy-plugin-add'), 'utf8')
const pluginEnable = fs.readFileSync(path.join(root, 'bin/omarchy-plugin-enable'), 'utf8')
assert(
  /Now using \$id as the bar/.test(pluginEnable)
    && /omarchy-plugin-enable "\$id" "\$\{ENABLE_PLACEMENT\[@\]\}"/.test(pluginAdd),
  'plugin enable reports a bar as replacing the one in use, whether enabled or freshly added'
)
assert(
  /\.barWidget\.defaultSection \/\/ "center"/.test(pluginAdd)
    && /gum choose[\s\S]*?--selected "\$default_section"/.test(pluginAdd),
  'interactive plugin add selects the manifest placement or center fallback by default'
)
assert(
  /"omarchy-plugin-\$1" "\$id"/.test(pluginPicker),
  'plugin picker delegates enable and disable without interpreting plugin kinds'
)
// Icons ride along as "<glyph>\tlabel\tsubtext"; the menu shows the glyph,
// renders the subtext under the label, and hands back "label\tsubtext" so the
// picker can act on the id without resolving a display name. What the picker
// then does with the row it gets back is checked in menu-plugin-test.sh.
assert(
  /\.name \+ \\"\\\\t\\" \+ \.id/.test(pluginPicker)
    && /id=\$\(cut -f2 <<<"\$selection"\)/.test(pluginPicker),
  'plugin picker shows the id as row subtext and acts on the id the selection hands back'
)
assert(
  /var icon = parts\.length > 1 \? parts\.shift\(\) : ""\s*\n\s*var label = parts\.shift\(\) \|\| ""\s*\n\s*var detail = parts\.join\("\\t"\)/.test(menuQml),
  'menu select mode reads a leading icon and a trailing subtext off an option'
)
assert(
  /omarchy-launch-floating-terminal-with-presentation "omarchy-plugin-remove/.test(pluginPicker),
  'plugin picker removes where the confirmation and backup path are visible'
)

// A font installed since the shell started should show up without a restart.
const providerBlock = menuQml.match(/readonly property var providers: \(\{[\s\S]*?\n  \}\)/)[0]
assert(
  /"fonts": \{[\s\S]*?volatile: true/.test(providerBlock),
  'menu re-enumerates the font list every time it is opened'
)
assert(
  /function setActiveMenu\([\s\S]*?root\.invalidateVolatileProvider\(id\)\s*\n\s*root\.loadProviderForMenu\(id\)/.test(menuQml)
    && /function openExistingMenu\([\s\S]*?invalidateVolatileProvider\(activeMenu\)\s*\n\s*loadProviderForMenu\(activeMenu\)/.test(menuQml),
  'menu invalidates volatile providers when entering a menu, not on every keystroke'
)
assert(
  ['loadProviderForMenu', 'loadProvidersForSearch'].every(
    name => !menuQml.match(new RegExp(`function ${name}\\([^)]*\\) \\{([\\s\\S]*?)\\n  \\}`))[1].includes('invalidateVolatileProvider')
  ),
  'menu search never restarts a volatile provider'
)
assertEqual(
  defaultById['trigger.hardware.laptop-display'].when,
  'omarchy-hw-laptop',
  'menu only shows Laptop Display on laptops'
)
assertEqual(
  defaultById['trigger.hardware.mirror-display'].when,
  'omarchy-hw-laptop',
  'menu only shows Mirror Display on laptops'
)
assertEqual(
  defaultById['trigger.capture.screenrecord.webcam'].when,
  'omarchy-hw-webcam',
  'menu only shows webcam screen recording when a webcam is available'
)
assert(
  /font\.family: row\.iconFont\.length > 0 \? row\.iconFont : root\.fontFamily/.test(menuQml),
  'menu rows support per-icon font families'
)

assert(
  /function select\(delta\)[\s\S]*root\.disarmPointer\(\)[\s\S]*selectedIndex =/.test(menuQml),
  'menu keyboard navigation disarms pointer selection'
)
// A dimmed row is not a target: the cursor steps over it, the pointer refuses
// to land on it, and neither Enter nor a click can reach it.
assert(
  /function select\(delta\)[\s\S]*?var target = root\.nextSelectable\(from, delta\)\s*\n\s*if \(target < 0\) return/.test(menuQml),
  'menu keyboard navigation skips disabled rows in the direction of travel'
)
assert(
  /function rowSelectable\(index\)[\s\S]*?return !displayModel\.get\(index\)\.disabled/.test(menuQml),
  'menu reads selectability off the row'
)
assert(
  /function activateIndex\(index, fromPointer\)[\s\S]*?if \(!root\.rowSelectable\(index\)\) return/.test(menuQml),
  'menu refuses to activate a disabled row'
)
assert(
  /function selectFromPointer\(index, item, mouse\)[\s\S]*?if \(!root\.rowSelectable\(index\)\) return/.test(menuQml)
    && /onClicked: \{\s*\n\s*if \(row\.disabled\) return/.test(menuQml),
  'menu leaves the cursor put when the pointer crosses a disabled row'
)
assert(
  /opacity: row\.disabled \? 0\.4 : 1/.test(menuQml) && !/font\.italic/.test(menuQml),
  'menu renders a disabled row faded, and leaves it at that'
)
assert(
  /function rebuildDisplay\(\)[\s\S]*?root\.settleCursor\(\)/.test(menuQml),
  'menu parks the cursor on a selectable row after the rows change'
)
// A menu with nothing selectable in it has no cursor, and Return must not
// conjure one onto a disabled row just because rows exist.
assert(
  /function settleCursor\(\)[\s\S]*?root\.cursorActive = target >= 0/.test(menuQml)
    && /else if \(root\.cursorActive\) root\.activateIndex\(root\.selectedIndex\)\s*\n\s*else root\.settleCursor\(\)/.test(menuQml),
  'menu ties the cursor to a selectable row existing, both ways'
)
assert(
  /function setFilter\(nextFilter\)[\s\S]*root\.disarmPointer\(\)/.test(menuQml),
  'menu filter changes disarm pointer selection'
)
assert(
  /function setActiveMenu\(id, pushHistory, fromPointer\)[\s\S]*if \(fromPointer\) pointerGate\.allowInitialSample\(\)\s*else root\.disarmPointer\(\)/.test(menuQml),
  'menu route changes only accept an initial pointer sample for mouse activation'
)
// Navigation keys are configuration now, so the dispatch must go through the
// bindings rather than test Qt.Key_* directly. Page scrolling in particular was
// lost once when the chain was rewritten and nothing here noticed.
assert(
  /checkKeyBinding\("back", event\)[\s\S]{0,80}root\.goBack\(\)/.test(menuQml)
    && !/Qt\.Key_Backspace \|\| event\.key === Qt\.Key_Left/.test(menuQml),
  'menu back navigation is driven by the back binding, not a hardcoded key test'
)
assert(
  /checkKeyBinding\("pageNext", event\)[\s\S]{0,80}root\.select\(6\)/.test(menuQml)
    && /checkKeyBinding\("pagePrev", event\)[\s\S]{0,80}root\.select\(-6\)/.test(menuQml),
  'menu still scrolls a page at a time, through the page bindings'
)
assert(
  /function checkKeyBinding\(action, event\) \{\s*\n\s*return MenuModel\.bindingMatches\(action, root\.keyBindings\[action\], event, root\.filterText\.length > 0\)/.test(menuQml),
  'menu delegates keybinding matching to the shared model'
)
assert(
  !/Qt\.Key_Down|Qt\.Key_Up|Qt\.Key_PageUp|Qt\.Key_PageDown|Qt\.Key_Return/.test(menuQml),
  'menu keeps no second copy of the navigation keys as Qt.Key_ constants'
)

// Escape and Delete are deliberately not bindable; a binding that shadowed
// Escape could leave a user with no way to close the menu.
assert(
  /event\.key === Qt\.Key_Escape/.test(menuQml) && /event\.key === Qt\.Key_Delete/.test(menuQml),
  'menu keeps Escape and Delete out of the binding table'
)

// --- keybindings --------------------------------------------------------

const keybindingsJsonc = `
{
  "keybindings": {
    "next": ["DOWN", "CTRL + J"],
    "back": ["LEFT", "CTRL + SHIFT + H"],
  },
  "personal": {"label":"Personal"},
}
`

// A keybindings block is menu-wide configuration. Parsed as an entry it becomes
// an empty submenu sitting on the root menu, searchable and routable.
const withKeybindings = menu.parseMenuJsonc(keybindingsJsonc)
assertDeepEqual(
  withKeybindings.map(entry => entry.id),
  ['personal'],
  'menu ignores the top-level keybindings key when reading entries'
)
assertEqual(
  menu.parseMenuJsonc('{"items":{"keybindings":{"label":"Keys"}}}').length,
  1,
  'menu still accepts an entry called keybindings under an explicit items wrapper'
)

const parsedBindings = menu.parseMenuKeybindings(keybindingsJsonc)
assertDeepEqual(
  parsedBindings.next,
  [
    { key: 0x01000015, modifiers: 0 },
    { key: 0x4a, modifiers: 0x04000000 }
  ],
  'menu resolves a binding string into Qt key and modifier values'
)
assertDeepEqual(
  parsedBindings.back,
  [
    { key: 0x01000012, modifiers: 0 },
    { key: 0x48, modifiers: 0x04000000 | 0x02000000 }
  ],
  'menu resolves every binding of an action and stacks modifiers'
)
// Runs fn with console.warn captured, and hands back what it returned alongside
// the warnings it emitted. Every keybinding path that refuses input warns, so
// asserting the refusal and the warning together is the shape these tests want.
function captureWarnings(fn) {
  const warnings = []
  const real = console.warn
  console.warn = message => warnings.push(message)
  try {
    return { value: fn(), warnings: warnings }
  } finally {
    console.warn = real
  }
}

// --- binding strings ----------------------------------------------------
//
// One binding is one string in the DSL config/hypr/bindings.lua writes. The
// spacing and capitalization a user reaches for must not change what it means.
const CTRL = 0x04000000
const SHIFT = 0x02000000
const ALT = 0x08000000
const SUPER = 0x10000000
const KEY_J = 0x4a
const KEY_DOWN = 0x01000015

for (const spelling of ['CTRL + J', 'Ctrl+J', 'ctrl + j', 'CTRL+J', '  CTRL  +  J  ', 'cTrL + j']) {
  assertDeepEqual(
    menu.parseBinding(spelling),
    { key: KEY_J, modifiers: CTRL },
    `menu reads ${JSON.stringify(spelling)} as the same binding`
  )
}

assertDeepEqual(menu.parseBinding('DOWN'), { key: KEY_DOWN, modifiers: 0 }, 'menu takes a bare key with no modifier')

// Punctuation needs no table entry: resolveKeyName's single-character fallback
// returns the character's own code, which is what a Qt.Key_ constant for a
// printable character is. KEY_NAME_MAP used to name these separately and every
// entry mapped to exactly this.
assertDeepEqual(menu.parseBinding('CTRL + ,'), { key: 0x2c, modifiers: CTRL }, 'menu resolves a punctuation key behind a modifier')
assertDeepEqual(menu.parseBinding('SHIFT + /'), { key: 0x2f, modifiers: SHIFT }, 'menu resolves a slash behind a modifier')

// comma, slash and print keep a name because Omarchy's own Hyprland bindings
// spell them that way, and the format's premise is that it matches the file
// users already edit. The named and character forms must not diverge.
assertDeepEqual(menu.parseBinding('CTRL + COMMA'), menu.parseBinding('CTRL + ,'), 'menu resolves CTRL + COMMA and CTRL + , identically')
assertDeepEqual(menu.parseBinding('SUPER + SLASH'), menu.parseBinding('SUPER + /'), 'menu resolves SUPER + SLASH and SUPER + / identically')
assertDeepEqual(menu.parseBinding('ALT + PRINT'), { key: 0x01000009, modifiers: ALT }, 'menu resolves PRINT, which Omarchy binds four times')
assertDeepEqual(menu.parseBinding('SUPER + grave'), { key: 0x60, modifiers: SUPER }, 'menu resolves grave, which tiling.lua binds twice')
assertDeepEqual(menu.parseBinding('SUPER + CTRL + PERIOD'), { key: 0x2e, modifiers: SUPER | CTRL }, 'menu resolves PERIOD, which utilities.lua binds')
assertDeepEqual(menu.parseBinding('grave'), menu.parseBinding('`'), 'menu resolves grave and the backtick identically')

// A punctuation name that was cut drops the binding rather than resolving to
// something else, and the typo guard then leaves the action as shipped.
const cut = captureWarnings(() => ({
  parsed: menu.parseBinding('CTRL + BRACKETLEFT'),
  merged: menu.mergeKeybindings(
    menu.normalizeKeybindings(menu.defaultKeybindings),
    menu.normalizeKeybindings({ next: ['CTRL + BRACKETLEFT'] })
  )
}))
const cutName = cut.value.parsed
const cutNameMerged = cut.value.merged
const cutNameWarnings = cut.warnings
assertEqual(cutName, null, 'menu drops a punctuation name it no longer carries')
assertEqual(cutNameWarnings.length, 2, 'menu warns each time the cut name is parsed')
assertDeepEqual(
  cutNameMerged.next,
  [{ key: KEY_DOWN, modifiers: 0 }],
  'menu keeps the shipped DOWN when the only binding given names a cut punctuation key'
)
assertDeepEqual(menu.parseBinding('CTRL + ['), { key: 0x5b, modifiers: CTRL }, 'menu still resolves the cut key by its character')
for (const [ch, code] of [['-', 0x2d], ['=', 0x3d], ['.', 0x2e], [';', 0x3b], ['\\', 0x5c], ["'", 0x27], ['`', 0x60], ['[', 0x5b], [']', 0x5d]]) {
  assertDeepEqual(menu.parseBinding(ch), { key: code, modifiers: 0 }, `menu resolves ${JSON.stringify(ch)} to its own character code`)
}
assertDeepEqual(menu.parseBinding('j'), { key: KEY_J, modifiers: 0 }, 'menu takes a bare single character')
assertDeepEqual(
  menu.parseBinding('SUPER + SHIFT + ALT + CTRL + J'),
  { key: KEY_J, modifiers: SUPER | SHIFT | ALT | CTRL },
  'menu stacks every modifier in the Hyprland vocabulary'
)
assertDeepEqual(
  menu.parseBinding('shift + super + j'),
  menu.parseBinding('SUPER + SHIFT + J'),
  'menu does not care what order the modifiers come in'
)

// Everything that does not resolve completely resolves to nothing. Falling back
// to the bare key is the failure mode this is written against.
const malformed = {
  'CTL + J': 'a misspelled modifier',
  'CONTROL + J': 'the Alacritty modifier word this format replaced',
  'CTRL +': 'a trailing separator with no key',
  '+ J': 'a leading separator with no modifier',
  'CTRL + NOPE': 'an unknown key name',
  '+': 'a lone separator',
  '': 'an empty string',
  '   ': 'nothing but whitespace',
  'CTRL + SHFIT + J': 'a misspelled modifier among good ones'
}
const malformedWarnings = captureWarnings(() => {
  for (const [spelling, description] of Object.entries(malformed)) {
    assertEqual(menu.parseBinding(spelling, 'next'), null, `menu refuses ${description}: ${JSON.stringify(spelling)}`)
  }
}).warnings
assertEqual(
  malformedWarnings.length,
  Object.keys(malformed).length - 2,
  'menu warns about every malformed binding except the two that are simply blank'
)
// The action is what locates the offending line in a user's file, so pin it
// rather than leaving it incidental to the count.
assertDeepEqual(
  malformedWarnings.filter(message => !/ for next$/.test(message)),
  [],
  'menu names the action in every malformed-binding warning'
)
assertDeepEqual(
  malformedWarnings.filter(message => !message.startsWith('menu keybindings: ')),
  [],
  'menu prefixes every keybinding warning so a journal grep finds them together'
)

assertEqual(menu.parseMenuKeybindings('{"personal":{}}'), null, 'menu keybindings are absent when the block is')
assertEqual(menu.parseMenuKeybindings('{ not json'), null, 'menu keybindings drop out when the file fails to parse')

// A typo would otherwise resolve to key 0 and bind nothing in silence.
const typoRun = captureWarnings(() => menu.parseMenuKeybindings('{"keybindings":{"next":["DWON","UP"]}}'))
const typo = typoRun.value
const warnings = typoRun.warnings
assertEqual(typo.next.length, 1, 'menu drops a binding whose key name does not resolve')
assertEqual(warnings.length, 1, 'menu warns about an unresolvable key name')
assertEqual(
  warnings[0],
  'menu keybindings: unknown key in "DWON" for next',
  'menu names the binding and the action in the unknown-key warning'
)

// Adding a key must not cost you the shipped one. Replacing outright was the
// old behavior, and it made "bind Ctrl+N to next" silently drop Down.
const shippedDefaults = menu.normalizeKeybindings(menu.defaultKeybindings)
const mergedBindings = menu.mergeKeybindings(
  shippedDefaults,
  menu.normalizeKeybindings({ next: ['CTRL + N'], back: [] })
)
assertDeepEqual(
  mergedBindings.next,
  [
    { key: 0x01000015, modifiers: 0 },
    { key: 0x4e, modifiers: 0x04000000 }
  ],
  'menu keybindings append the user keys to the shipped ones for that action'
)
assert(
  mergedBindings.next.some(combo => combo.key === 0x01000015 && combo.modifiers === 0),
  'menu keybindings leave Down bound when the user block only names next'
)
assertEqual(mergedBindings.back.length, 0, 'menu keybindings treat an empty list as unbinding the action')
assertEqual(mergedBindings.prev[0].key, 0x01000013, 'menu keybindings leave actions the user did not list alone')
assertDeepEqual(
  shippedDefaults.next,
  [{ key: 0x01000015, modifiers: 0 }],
  'menu keybindings merge does not write back into the defaults it was given'
)

// An action the user names is only unbound when it is written as [] — a block
// whose keys all fail to resolve leaves the shipped keys alone instead.
const typoMergedRun = captureWarnings(() => menu.mergeKeybindings(
  menu.normalizeKeybindings(menu.defaultKeybindings),
  menu.normalizeKeybindings({ next: ['DWON'] })
))
const typoMerged = typoMergedRun.value
const typoWarnings = typoMergedRun.warnings
assertEqual(typoMerged.next.length, 1, 'menu keeps the shipped keys when every key the user listed is unresolvable')
assertEqual(typoMerged.next[0].key, 0x01000015, 'menu leaves Down bound after a typo rather than unbinding the action')
assertEqual(typoWarnings.length, 1, 'menu warns once about the unresolvable key')

// The bare-J regression, end to end. "CTL + J" is the misspelling a user
// reaches for coming from Hyprland's CTRL; if its modifier fell away, the
// binding would land on plain J. The dispatch consults bindings before it
// treats a keystroke as typing (Menu.qml checks every action ahead of the
// printable-character branch), so a live bare-J binding does not just navigate
// by accident -- it takes the letter J away from menu search for good.
const badModRun = captureWarnings(() => menu.mergeKeybindings(
  menu.normalizeKeybindings(menu.defaultKeybindings),
  menu.normalizeKeybindings({ next: ['CTL + J'] })
))
const badMod = badModRun.value
const badModWarnings = badModRun.warnings
assert(
  !menu.bindingMatches('next', badMod.next, { key: KEY_J, modifiers: 0 }, false),
  'menu leaves the letter J available to search when a binding names a modifier it cannot parse'
)
assert(
  !menu.bindingMatches('next', badMod.next, { key: KEY_J, modifiers: CTRL }, false),
  'menu does not half-bind a misspelled modifier onto the real chord either'
)
assertEqual(badModWarnings.length, 1, 'menu warns once about the modifier it could not parse')
assertEqual(
  badModWarnings[0],
  'menu keybindings: unknown modifier in "CTL + J" for next',
  'menu names the binding and the action in the unknown-modifier warning'
)

// ... and it composes with the typo guard: every binding of the action failed,
// so the action is left out of the user block entirely and the shipped keys
// survive rather than being unbound.
assertDeepEqual(
  badMod.next,
  [{ key: KEY_DOWN, modifiers: 0 }],
  'menu keeps the shipped DOWN when every binding the user gave the action fails to parse'
)
assert(
  menu.bindingMatches('next', badMod.next, { key: KEY_DOWN, modifiers: 0 }, false),
  'menu still navigates on DOWN after a whole action failed to parse'
)

const userOnlyAction = menu.mergeKeybindings(
  menu.normalizeKeybindings(menu.defaultKeybindings),
  menu.normalizeKeybindings({ pageNext: ['CTRL + F'] })
)
assertEqual(userOnlyAction.pageNext.length, 2, 'menu appends to an action the defaults already bind')

const ctrlJ = { key: 0x4a, modifiers: 0x04000000 }
assert(menu.bindingMatches('next', parsedBindings.next, ctrlJ, false), 'menu matches a modified binding')
assert(
  !menu.bindingMatches('next', parsedBindings.next, { key: 0x4a, modifiers: 0x04000000 | 0x02000000 }, false),
  'menu requires an exact modifier match so Ctrl+Shift+J does not fire Ctrl+J'
)
assert(!menu.bindingMatches('next', parsedBindings.next, { key: 0x4a, modifiers: 0 }, false), 'menu does not fire a modified binding on the bare key')

// --- back yields to a filter being typed --------------------------------
//
// One rule replaces the per-binding whenFilterEmpty flag: an unmodified back
// binding stands down while the search box has text. It is scoped to back
// because back is the action whose unmodified keys are ones a hand reaches for
// mid-search; the other actions must keep driving a filtered list.
const left = { key: 0x01000012, modifiers: 0 }
const backspace = { key: 0x01000003, modifiers: 0 }
const ctrlShiftH = { key: 0x48, modifiers: 0x04000000 | 0x02000000 }
const shippedForFilter = menu.parseMenuKeybindings(defaultMenuJsonc)
const shippedBack = shippedForFilter.back

assert(menu.bindingMatches('back', shippedBack, left, false), 'menu goes back on LEFT when the filter is empty')
assert(!menu.bindingMatches('back', shippedBack, left, true), 'menu does not go back on LEFT while the filter has text')

// Backspace never reaches the binding table with text in the filter --
// Util.editsFilter claims it first -- so what matters is that the empty-filter
// answer is the one it always was, and that the rule agrees with the
// interception rather than contradicting it.
assert(menu.bindingMatches('back', shippedBack, backspace, false), 'menu goes back on BACKSPACE when the filter is empty')
assert(!menu.bindingMatches('back', shippedBack, backspace, true), 'menu does not go back on BACKSPACE while the filter has text')

assert(
  menu.bindingMatches('back', parsedBindings.back, ctrlShiftH, true),
  'menu still goes back on a modified binding while filtering'
)
const ctrlH = menu.normalizeKeybindings({ back: ['CTRL + H'] }).back
assert(menu.bindingMatches('back', ctrlH, { key: 0x48, modifiers: 0x04000000 }, true), 'menu goes back on CTRL + H mid-search')
assert(menu.bindingMatches('back', ctrlH, { key: 0x48, modifiers: 0x04000000 }, false), 'menu goes back on CTRL + H with an empty filter too')

// A user who binds a bare letter to back gets navigation on an empty filter and
// the letter back the moment they start typing -- which is the whole reason the
// rule keys off modifiers rather than off the key.
const bareH = menu.normalizeKeybindings({ back: ['H'] }).back
assert(menu.bindingMatches('back', bareH, { key: 0x48, modifiers: 0 }, false), 'menu goes back on a bare H bound to back when nothing is typed')
assert(
  !menu.bindingMatches('back', bareH, { key: 0x48, modifiers: 0 }, true),
  'menu leaves a bare H bound to back to the filter, so it types an h while searching'
)

// The rule is back's alone. A filtered list still has to be navigable.
assert(
  menu.bindingMatches('next', shippedForFilter.next, { key: 0x01000015, modifiers: 0 }, true),
  'menu still navigates on DOWN while the filter has text'
)
assert(
  menu.bindingMatches('activate', shippedForFilter.activate, { key: 0x01000004, modifiers: 0 }, true),
  'menu still activates on RETURN while the filter has text'
)

// The shipped block is the source of truth; the constant is only the fallback
// for an unreadable default file, so both have to cover the whole dispatch.
const shippedBindings = menu.parseMenuKeybindings(defaultMenuJsonc)
const dispatchedActions = [...menuQml.matchAll(/checkKeyBinding\("(\w+)"/g)].map(match => match[1])
assertDeepEqual(
  dispatchedActions.filter(action => !shippedBindings[action]),
  [],
  'menu ships a default binding for every action its key dispatch calls'
)
assertDeepEqual(
  dispatchedActions.filter(action => !menu.defaultKeybindings[action]),
  [],
  'menu keybinding fallback covers every action its key dispatch calls'
)

// --- the fallback actually reaches the dispatch --------------------------
//
// docs/menu.md promises a missing or unparseable default file cannot leave the
// menu without a keyboard. That promise was silently broken until 1a72c317 --
// the call site named an export alias QML cannot see, so the fallback resolved
// to null -- and nothing here noticed, because every assertion above tests the
// constant rather than the path that reaches it. Both paths, since the file has
// two failure modes and only one of them runs onLoaded.

// Path 1: a file that never loads. defaultMenuFile declares onLoaded and
// onFileChanged but no onLoadFailed, so nothing assigns defaultKeyBindings and
// the property initializer is the whole of the fallback.
const defaultFileBlock = menuQml.match(/FileView \{\s*\n\s*id: defaultMenuFile[\s\S]*?\n  \}/)[0]
assert(
  !/onLoadFailed/.test(defaultFileBlock),
  'menu default file has no onLoadFailed, so the property initializer is what covers a file that never loads'
)
assert(
  /property var defaultKeyBindings: root\.fallbackKeyBindings\(\)/.test(menuQml),
  'menu initializes defaultKeyBindings from the fallback rather than to null or []'
)

// Path 2: a file that loads as garbage. onLoaded takes the || branch.
assert(
  /root\.defaultKeyBindings = root\.parseMenuKeybindings\(raw\) \|\| root\.fallbackKeyBindings\(\)/.test(menuQml),
  'menu falls back to the constant when a default file loads but yields no keybindings'
)

// fallbackKeyBindings resolves the constant through the same normalizer a file
// goes through, so what the two paths produce is comparable to what a working
// file produces.
const fallbackCall = menuQml.match(/function fallbackKeyBindings\(\) \{\s*\n\s*return ([^\n]+)/)[1]
assertEqual(
  fallbackCall.trim(),
  'MenuModel.normalizeKeybindings(MenuModel.DEFAULT_KEYBINDINGS)',
  'menu fallback resolves the constant by its top-level declaration through the shared normalizer'
)

// Now the behaviour both paths land on: whatever the default file did, every
// action the dispatch calls is still bound to something.
const fallbackBindings = menu.normalizeKeybindings(menu.defaultKeybindings)
for (const raw of ['', '   ', '{ not json', '{}', '{"apps":{"label":"Apps"}}', '{"keybindings":"nonsense"}']) {
  const parsed = menu.parseMenuKeybindings(raw)
  const resolved = menu.mergeKeybindings(parsed || fallbackBindings, null)
  assertDeepEqual(
    dispatchedActions.filter(action => !resolved[action] || resolved[action].length === 0),
    [],
    `menu keeps every dispatched action bound when the default file is ${JSON.stringify(raw)}`
  )
}

// And the keys are the real ones, not merely a non-empty list.
const unreadable = menu.mergeKeybindings(menu.parseMenuKeybindings('{ not json') || fallbackBindings, null)
assert(menu.bindingMatches('next', unreadable.next, { key: KEY_DOWN, modifiers: 0 }, false), 'menu still navigates on DOWN with an unreadable default file')
assert(menu.bindingMatches('activate', unreadable.activate, { key: 0x01000004, modifiers: 0 }, false), 'menu still activates on RETURN with an unreadable default file')
assert(menu.bindingMatches('back', unreadable.back, { key: 0x01000012, modifiers: 0 }, false), 'menu still goes back on LEFT with an unreadable default file')

// Where the promise stops. An empty block in the DEFAULT file parses to {},
// which is truthy, so the || does not fire and nothing is bound -- that is the
// base saying "bind nothing", not a file that failed to load, and it is the
// coherent reading given that the same {} in the USER file means "override
// nothing". Pinned so the boundary is a decision on record rather than a
// surprise; menu-test's shipped-block assertion is what guards the real file.
const emptyBlock = menu.parseMenuKeybindings('{"keybindings":{}}')
assertDeepEqual(emptyBlock, {}, 'menu reads an empty keybindings block as an empty binding set, not as a failure to parse')
assertDeepEqual(
  menu.mergeKeybindings(fallbackBindings, menu.parseMenuKeybindings('{"keybindings":{}}')).next,
  fallbackBindings.next,
  'menu treats the same empty block in a user extension as overriding nothing'
)

// A user extension must not be able to leave an action unbound by unbinding it
// while the default file is also unreadable -- that is the one case where [] and
// a broken default meet.
const unboundOnBroken = menu.mergeKeybindings(fallbackBindings, menu.normalizeKeybindings({ next: [] }))
assertEqual(unboundOnBroken.next.length, 0, 'menu honours an explicit unbind even when the defaults came from the fallback')
assert(
  menu.bindingMatches('prev', unboundOnBroken.prev, { key: 0x01000013, modifiers: 0 }, false),
  'menu leaves the other actions bound when one is unbound against the fallback'
)

// --- modifier parity with the chain this replaced ------------------------
//
// The hardcoded dispatch tested `event.key === Qt.Key_Down` with no modifier
// check, so SHIFT + DOWN moved the selection and CTRL + RETURN activated. An
// unmodified binding on a non-character key keeps ignoring what was held, or
// this PR would quietly change how the shipped arrows behave.
const shippedParity = menu.parseMenuKeybindings(defaultMenuJsonc)
for (const [label, mods] of [['SHIFT', SHIFT], ['CTRL', CTRL], ['ALT', ALT], ['CTRL+SHIFT', CTRL | SHIFT], ['SUPER', SUPER]]) {
  assert(
    menu.bindingMatches('next', shippedParity.next, { key: KEY_DOWN, modifiers: mods }, false),
    `menu navigates on ${label}+DOWN, as the hardcoded chain did`
  )
}
assert(
  menu.bindingMatches('activate', shippedParity.activate, { key: 0x01000004, modifiers: CTRL }, false),
  'menu activates on CTRL+RETURN, as the hardcoded chain did'
)
assert(
  menu.bindingMatches('pageNext', shippedParity.pageNext, { key: 0x01000017, modifiers: ALT }, false),
  'menu pages on ALT+PAGEDOWN, as the hardcoded chain did'
)
assert(
  menu.bindingMatches('back', shippedParity.back, { key: 0x01000012, modifiers: SHIFT }, false),
  'menu goes back on SHIFT+LEFT with an empty filter, as the hardcoded chain did'
)
assert(
  !menu.bindingMatches('back', shippedParity.back, { key: 0x01000012, modifiers: SHIFT }, true),
  'menu still holds SHIFT+LEFT back while the filter has text, as the hardcoded chain did'
)

// Character keys stay exact, or the letter would be lost from search, and a
// binding that names its own modifiers stays exact in both directions.
const bareJ = menu.normalizeKeybindings({ next: ['J'] }).next
const ctrlJonly = menu.normalizeKeybindings({ next: ['CTRL + J'] }).next
assert(!menu.bindingMatches('next', bareJ, { key: KEY_J, modifiers: CTRL }, false), 'menu does not fire a bare J binding on CTRL + J')
assert(!menu.bindingMatches('next', ctrlJonly, { key: KEY_J, modifiers: 0 }, false), 'menu does not fire a CTRL + J binding on bare J')
assert(
  !menu.bindingMatches('next', ctrlJonly, { key: KEY_J, modifiers: CTRL | SHIFT }, false),
  'menu still keeps CTRL + SHIFT + J off a CTRL + J binding after the parity rule'
)

// The two must stay separable: J and CTRL + J on different actions both fire.
const split = menu.mergeKeybindings(
  menu.normalizeKeybindings(menu.defaultKeybindings),
  menu.normalizeKeybindings({ next: ['CTRL + J'], activate: ['J'] })
)
assert(menu.bindingMatches('next', split.next, { key: KEY_J, modifiers: CTRL }, false), 'menu fires the CTRL + J binding when both J and CTRL + J are bound')
assert(menu.bindingMatches('activate', split.activate, { key: KEY_J, modifiers: 0 }, false), 'menu fires the bare J binding when both J and CTRL + J are bound')
assert(!menu.bindingMatches('activate', split.activate, { key: KEY_J, modifiers: CTRL }, false), 'menu does not let CTRL + J reach the bare J action')

// Qt sets Qt.KeypadModifier (0x20000000) on everything the numeric keypad
// sends, and Key_Enter is the keypad's Return by definition, so the shipped
// "ENTER" binding always arrives carrying the bit. Requiring an exact
// modifier match without clearing it took keypad Enter and the keypad arrows
// away from the menu -- a regression against the pre-binding dispatch, which
// tested Key_Enter with no modifier check at all.
const KEYPAD = 0x20000000
assert(
  menu.bindingMatches('activate', shippedBindings.activate, { key: 0x01000005, modifiers: KEYPAD }, false),
  'menu activates on keypad Enter, which Qt always flags as a keypad key'
)
assert(
  menu.bindingMatches('activate', shippedBindings.activate, { key: 0x01000004, modifiers: 0 }, false),
  'menu still activates on the main Return'
)
assert(
  menu.bindingMatches('next', shippedBindings.next, { key: 0x01000015, modifiers: KEYPAD }, false)
    && menu.bindingMatches('prev', shippedBindings.prev, { key: 0x01000013, modifiers: KEYPAD }, false),
  'menu navigates on the keypad arrows'
)
assert(
  menu.bindingMatches('pageNext', shippedBindings.pageNext, { key: 0x01000017, modifiers: KEYPAD }, false),
  'menu pages on the keypad PageDown'
)
assert(
  menu.bindingMatches('back', shippedBindings.back, { key: 0x01000012, modifiers: KEYPAD }, false),
  'menu goes back on the keypad Left'
)

// Only the keypad bit is cleared. Every modifier a user can actually hold must
// still match exactly, or the mask would have bought keypad Enter at the cost
// of the rule that keeps Ctrl+Shift+J off a Ctrl+J binding.
assert(
  !menu.bindingMatches('next', parsedBindings.next, { key: 0x4a, modifiers: 0x04000000 | 0x02000000 }, false),
  'menu keeps Ctrl+Shift+J off a Ctrl+J binding after the keypad bit is masked'
)
assert(
  !menu.bindingMatches('next', parsedBindings.next, { key: 0x4a, modifiers: 0x04000000 | 0x02000000 | KEYPAD }, false),
  'menu does not let the keypad bit smuggle Ctrl+Shift+J onto a Ctrl+J binding'
)
assert(
  menu.bindingMatches('next', parsedBindings.next, { key: 0x4a, modifiers: 0x04000000 | KEYPAD }, false),
  'menu still matches Ctrl+J when the event also carries the keypad bit'
)
// quattro's chain tested Qt.Key_Enter with no modifier check (Menu.qml:1154
// there), so ALT + keypad Enter activated. The parity rule keeps that; the
// stricter assertion this replaces was encoding the regression.
assert(
  menu.bindingMatches('activate', shippedBindings.activate, { key: 0x01000005, modifiers: 0x08000000 | KEYPAD }, false),
  'menu activates on Alt+keypad Enter, as the hardcoded chain did'
)
assert(
  /PointerMoveGate\s*\{[\s\S]*id: pointerGate[\s\S]*referenceItem: card[\s\S]*\}/.test(menuQml),
  'menu uses shared pointer movement gate in card coordinates'
)
assert(
  /function disarmPointer\(\)[\s\S]*pointerGate\.reset\(\)/.test(menuQml),
  'menu resets pointer movement gate when pointer selection is disarmed'
)
// App rows are rebuilt from scratch on every desktop-entry rescan. The merge
// must be idempotent and must never carry an orphan id forward, or a single
// lost write turns into an app listed twice (and thrice, and so on).
const nonAppItems = {
  root: { id: 'root', kind: 'menu', label: 'Go' },
  apps: { id: 'apps', kind: 'menu', label: 'Apps', provider: 'apps' }
}
const nonAppOrder = ['root', 'apps']
const appRowsFor = ids => ids.map(id => ({ id: `apps.${id}`, kind: 'app', parent: 'apps', label: id, appId: id }))

const firstMerge = menu.mergeAppRows(nonAppItems, nonAppOrder, appRowsFor(['alacritty', 'youtube']))
assert(
  firstMerge.itemOrder.join(',') === 'root,apps,apps.alacritty,apps.youtube',
  'app merge appends app rows after the static menu items'
)

const secondMerge = menu.mergeAppRows(firstMerge.items, firstMerge.itemOrder, appRowsFor(['alacritty', 'youtube']))
assert(
  secondMerge.itemOrder.join(',') === 'root,apps,apps.alacritty,apps.youtube',
  'repeating the app merge with the same entries does not duplicate rows'
)

assert(
  menu.mergeAppRows(secondMerge.items, secondMerge.itemOrder, appRowsFor(['alacritty'])).itemOrder.join(',')
    === 'root,apps,apps.alacritty',
  'app merge drops rows for entries that went away'
)

assert(
  menu.mergeAppRows(nonAppItems, nonAppOrder, appRowsFor(['youtube', 'youtube'])).itemOrder.join(',')
    === 'root,apps,apps.youtube',
  'app merge lists an app once even when two desktop entries share an id'
)

const orphanedItems = {}
for (const key in firstMerge.items) orphanedItems[key] = firstMerge.items[key]
delete orphanedItems['apps.youtube']
const healed = menu.mergeAppRows(orphanedItems, firstMerge.itemOrder, appRowsFor(['alacritty', 'youtube']))
assert(
  healed.itemOrder.join(',') === 'root,apps,apps.alacritty,apps.youtube'
    && !!healed.items['apps.youtube'],
  'app merge heals an order entry whose item went missing instead of duplicating it'
)

assert(
  !firstMerge.items['apps.youtube'].hasOwnProperty('__probe')
    && (() => {
      const before = Object.keys(nonAppItems).length
      menu.mergeAppRows(nonAppItems, nonAppOrder, appRowsFor(['gimp']))
      return Object.keys(nonAppItems).length === before
    })(),
  'app merge leaves the map it was handed untouched'
)

const providerRowsFor = values => values.map(value => ({ id: `style.font.${value}`, kind: 'action', parent: 'style.font', label: value }))
const firstProviderMerge = menu.swapProviderRows(nonAppItems, nonAppOrder, 'style.font', providerRowsFor(['mono', 'serif']))
assert(
  firstProviderMerge.itemOrder.join(',') === 'root,apps,style.font.mono,style.font.serif',
  'provider merge appends its rows'
)
assert(
  menu.swapProviderRows(firstProviderMerge.items, firstProviderMerge.itemOrder, 'style.font', providerRowsFor(['mono', 'serif']))
    .itemOrder.join(',') === 'root,apps,style.font.mono,style.font.serif',
  'repeating a provider merge does not duplicate rows'
)
// A plugin drops out of the Enable list the moment it is enabled, so a
// provider that runs again has to lose the rows it contributed last time.
const rerunProviderMerge = menu.swapProviderRows(firstProviderMerge.items, firstProviderMerge.itemOrder, 'style.font', providerRowsFor(['serif']))
assert(
  rerunProviderMerge.itemOrder.join(',') === 'root,apps,style.font.serif',
  'provider merge drops rows the provider no longer lists'
)
assert(
  menu.swapProviderRows(firstProviderMerge.items, firstProviderMerge.itemOrder, 'style.other', providerRowsFor([]))
    .itemOrder.join(',') === 'root,apps,style.font.mono,style.font.serif',
  'provider merge leaves rows belonging to another provider alone'
)
// Rows are keyed by id, so a provider handing over two rows with the same id
// would lose one. Distinct plugin ids can slugify alike, which is why the
// menu makes each row id its own before merging.
assertEqual(
  ['acme.foo', 'acme_foo', 'acme-foo'].map(menu.slugify).join(','),
  'acme-foo,acme-foo,acme-foo',
  'menu slugs collide across plugin ids that differ only in separator'
)
assert(
  /var rowId = menuId \+ "\." \+ root\.slugify\(value\)\s*\n\s*while \(takenIds\[rowId\]\) rowId \+= "-"/.test(menuQml),
  'menu keeps colliding provider rows apart so none is dropped'
)

// The maps live in QML `var` properties, where an in-place write is
// occasionally dropped by the engine, so both merges must hand back fresh
// objects for the caller to assign in one shot.
assert(
  /var merged = MenuModel\.mergeAppRows\(root\.items, root\.itemOrder, appRows\)\s*\n\s*root\.items = merged\.items\s*\n\s*root\.itemOrder = merged\.itemOrder/.test(menuQml),
  'menu assigns the rebuilt app item map instead of mutating it in place'
)
assert(
  /var merged = MenuModel\.swapProviderRows\(root\.items, root\.itemOrder, menuId, providerRows\)\s*\n[\s\S]*?root\.items = merged\.items\s*\n\s*root\.itemOrder = merged\.itemOrder/.test(menuQml),
  'menu assigns the rebuilt provider item map instead of mutating it in place'
)
assert(
  !/root\.items\[[^\]]+\] =/.test(menuQml) && !/delete root\.items\[/.test(menuQml),
  'menu never writes into the item map held by the var property'
)

for (const functionName of ['openExistingMenu', 'openDmenu']) {
  const openMatch = menuQml.match(new RegExp(`function ${functionName}\\([^)]*\\) \\{([\\s\\S]*?)\\n  \\}`))
  assert(openMatch, `menu ${functionName} function exists`)
  assert(
    openMatch[1].indexOf('root.disarmPointer()') < openMatch[1].indexOf('opened = true')
      && !openMatch[1].includes('pointerGate.allowInitialSample()'),
    `menu ${functionName} ignores a stale hidden-pointer position when becoming visible`
  )
}
assert(
  /function selectFromPointer\(index, item, mouse\)[\s\S]*pointerGate\.moved\(item, mouse\)[\s\S]*root\.selectedIndex = index/.test(menuQml),
  'menu only selects from pointer after real movement'
)
assert(
  /onPositionChanged: function\(mouse\) \{\s*root\.selectFromPointer\(row\.index, row, mouse\)\s*\}/.test(menuQml),
  'menu row hover routes through pointer movement gate'
)
assert(
  /onEntered: root\.selectFromPointer\(row\.index, row, \{\s*x: mouseArea\.mouseX,\s*y: mouseArea\.mouseY\s*\}\)/.test(menuQml),
  'menu samples pointer movement immediately when entering a row'
)
assert(
  /function activateIndex\(index, fromPointer\)[\s\S]*root\.setActiveMenu\(row\.target \|\| row\.itemId, true, fromPointer\)/.test(menuQml)
    && /onClicked:[\s\S]*root\.activateIndex\(row\.index, true\)/.test(menuQml),
  'mouse activation carries pointer intent into subordinate menus'
)
JS

font_charset=$(fc-query --format='%{charset}' "$ROOT/default/fonts/omarchy/omarchy.ttf")
[[ $font_charset == *"e900-e90a"* ]] || fail "Omarchy icon font includes every custom menu glyph"
pass "Omarchy icon font includes the official agent marks"
