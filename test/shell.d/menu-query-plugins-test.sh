#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')

// A minimal plugin map: a math plugin, a web plugin, and a keyword-triggered
// copy plugin. Mirrors the built-ins shipped in Menu.qml.
const plugins = {
  'omarchy.query.calc': { id: 'omarchy.query.calc', kind: 'math', label: 'Calc', action: 'copy', command: 'omarchy-query-calc', enabled: true },
  'omarchy.query.web': { id: 'omarchy.query.web', kind: 'web', label: 'Web', action: 'run', command: 'omarchy-query-web', enabled: true },
  'omarchy.query.g': { id: 'omarchy.query.g', kind: 'copy', label: 'Google', action: 'copy', command: 'omarchy-query-web', keyword: 'g ', enabled: true },
}

// looksLikeMath: arithmetic needs a digit and an operator, and must reject URLs.
assert(menu.looksLikeMath('2+2'), 'detects 2+2 as math')
assert(menu.looksLikeMath('sqrt(9)'), 'detects sqrt(9) as math')
assert(menu.looksLikeMath('3*4-1'), 'detects 3*4-1 as math')
assert(!menu.looksLikeMath('hello world'), 'free text is not math')
assert(!menu.looksLikeMath('https://example.com'), 'a URL is not math')
assert(!menu.looksLikeMath('justwords'), 'words with no digits are not math')

// queryPluginsForQuery: math fires for arithmetic; web ALWAYS fires as a
// fallback (Alfred-style), so a query like 2+2 yields both — math first.
const mathActive = menu.queryPluginsForQuery(plugins, '2+2').map(p => p.id)
assert(mathActive.indexOf('omarchy.query.calc') >= 0, 'math plugin fires for 2+2')
assert(mathActive.indexOf('omarchy.query.web') >= 0, 'web plugin fires as fallback for 2+2')
assertEqual(mathActive[0], 'omarchy.query.calc', 'math is the first (default) result')
assertEqual(mathActive[1], 'omarchy.query.web', 'web is the second (arrow-down) result')

const webActive = menu.queryPluginsForQuery(plugins, 'weather tomorrow').map(p => p.id)
assert(webActive.indexOf('omarchy.query.web') >= 0, 'web plugin fires for free text')
assert(webActive.indexOf('omarchy.query.calc') < 0, 'math plugin does not fire for free text')

// A bare URL fires the web plugin, which passes the URL through so Enter opens
// it directly (omarchy-query-web --print echoes bare URLs verbatim).
const urlActive = menu.queryPluginsForQuery(plugins, 'https://example.com').map(p => p.id)
assert(urlActive.indexOf('omarchy.query.web') >= 0, 'web plugin fires for a bare URL')
assert(urlActive.indexOf('omarchy.query.calc') < 0, 'math plugin does not fire for a URL')

// Ranking is explicit, not insertion order: a user-defined math plugin merged
// after the built-in web plugin still ranks above it.
const userMathMap = {
  'omarchy.query.web': plugins['omarchy.query.web'],
  'com.example.math': { id: 'com.example.math', kind: 'math', label: 'M', action: 'copy', command: 'true', enabled: true },
}
const ranked = menu.queryPluginsForQuery(userMathMap, '2+2').map(p => p.id)
assertEqual(ranked[0], 'com.example.math', 'user math plugin ranks above built-in web')
assertEqual(ranked[1], 'omarchy.query.web', 'web stays last (fallback)')

// Keyword-triggered plugins fire only when the query starts with the keyword.
const kwActive = menu.queryPluginsForQuery(plugins, 'g cats').map(p => p.id)
assert(kwActive.indexOf('omarchy.query.g') >= 0, 'keyword plugin fires for "g cats"')
const noKwActive = menu.queryPluginsForQuery(plugins, 'go home').map(p => p.id)
assert(noKwActive.indexOf('omarchy.query.g') < 0, 'keyword plugin stays dormant for "go home"')

// Disabled plugins never fire.
const disabledMap = JSON.parse(JSON.stringify(plugins))
disabledMap['omarchy.query.calc'].enabled = false
const disabledActive = menu.queryPluginsForQuery(disabledMap, '2+2').map(p => p.id)
assert(disabledActive.indexOf('omarchy.query.calc') < 0, 'disabled math plugin does not fire')

// queryPluginRow: math shows "query = result"; copy/run carry a localized detail.
const calcRow = menu.queryPluginRow(plugins['omarchy.query.calc'], '2+2', '4', 'en')
assertEqual(calcRow.label, '2+2 = 4', 'math row labels query = result')
assertEqual(calcRow.kind, 'query', 'result row kind is query')
assertEqual(calcRow.section, 'results', 'result row sits in the results section')
assertEqual(calcRow.detail, 'Copy to clipboard', 'copy action detail localizes to English')

const calcRowEs = menu.queryPluginRow(plugins['omarchy.query.calc'], '2+2', '4', 'es')
assertEqual(calcRowEs.detail, 'Copiar al portapapeles', 'copy action detail localizes to Spanish')

const webRow = menu.queryPluginRow(plugins['omarchy.query.web'], 'weather', 'ignored', 'en')
assertEqual(webRow.detail, 'Open', 'run action detail is Open')

// Icons: the plugin's own icon wins for every kind; math/web fall back to the
// bundled calc/search keys only when the plugin defines none.
const iconPlugin = { id: 'p.icon', kind: 'copy', label: 'Clip', icon: '󰅌', action: 'copy', command: 'echo', keyword: '> ' }
assertEqual(menu.queryPluginRow(iconPlugin, '> hi', 'hi', 'en').icon, '󰅌', 'copy row keeps the plugin icon')
assertEqual(menu.queryPluginRow({ id: 'p.m', kind: 'math', action: 'copy', command: 'x' }, '2+2', '4', 'en').icon, 'calc', 'math row falls back to bundled calc icon')
assertEqual(menu.queryPluginRow({ id: 'p.w', kind: 'web', action: 'run', command: 'x' }, 'q', 'u', 'en').icon, 'search', 'web row falls back to bundled search icon')

// copy/run/snippet rows surface the plugin's localized label as the detail
// (result value stays the prominent label).
const clipRow = menu.queryPluginRow(iconPlugin, '> hello', 'hello', 'en')
assertEqual(clipRow.label, 'hello', 'copy row label is the result value')
assertEqual(clipRow.detail, 'Clip', 'copy row detail is the plugin label')

// queryPluginLabel: i18n beats label beats id.
const i18nPlugin = { id: 'p.x', kind: 'web', label: 'X', i18n: { en: 'X (en)', es: 'X (es)' } }
assertEqual(menu.queryPluginLabel(i18nPlugin, 'es'), 'X (es)', 'i18n label wins for es')
assertEqual(menu.queryPluginLabel(i18nPlugin, 'en'), 'X (en)', 'i18n label wins for en')
assertEqual(menu.queryPluginLabel({ id: 'p.y', label: 'Y' }, 'en'), 'Y', 'falls back to label')
assertEqual(menu.queryPluginLabel({ id: 'p.z' }, 'en'), 'p.z', 'falls back to id')

// queryEncode round-trips through the same rule the launcher uses.
assertEqual(menu.queryEncode('a b'), 'a%20b', 'queryEncode percent-escapes spaces')
JS
