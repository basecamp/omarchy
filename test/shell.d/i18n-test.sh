#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const i18n = requireFromRoot('shell/Commons/I18nModel.js')

assertEqual(i18n.normalizeLocale('es_AR.UTF-8'), 'es_AR', 'locale normalization strips encoding')
assertEqual(i18n.normalizeLocale('es-ar@latin'), 'es_AR', 'locale normalization canonicalizes separators')
assertDeepEqual(i18n.localeCandidates({ LANG: 'es_AR.UTF-8' }), ['es_AR', 'es'], 'regional locale falls back to language')
assertDeepEqual(i18n.localeCandidates({ LANGUAGE: 'es_AR:es:en', LANG: 'en_US.UTF-8' }), ['es_AR', 'es', 'en'], 'LANGUAGE takes precedence')
assertEqual(i18n.selectCatalog({ LANGUAGE: 'fr_FR:es_AR:en' }, ['es']), 'es', 'LANGUAGE falls through its preference list')
assertEqual(i18n.selectCatalog({ LANG: 'es_AR.UTF-8' }, ['es']), 'es', 'language catalog matches regional locale')
assertEqual(i18n.selectCatalog({ LANG: 'en_US.UTF-8' }, ['es']), '', 'unsupported locale uses source strings')
assertEqual(i18n.translate('Search...', { 'Search...': 'Buscar…' }), 'Buscar…', 'known source string is translated')
assertEqual(i18n.translate('Unknown', { 'Search...': 'Buscar…' }), 'Unknown', 'missing translation falls back to source')
assertEqual(i18n.translate('Hello %1', { 'Hello %1': 'Hola %1' }, ['Ana']), 'Hola Ana', 'translation arguments are interpolated')

const catalog = JSON.parse(fs.readFileSync(path.join(root, 'shell/translations/es.json'), 'utf8'))
assertEqual(catalog['Enter Password'], 'Introduce la contraseña', 'Spanish catalog parses and exposes lock text')

const menuModel = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuSource = fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')
for (const entry of menuModel.parseMenuJsonc(menuSource)) {
  for (const field of ['label', 'title', 'description']) {
    const key = entry[field]
    if (key) assert(Object.prototype.hasOwnProperty.call(catalog, key), 'Spanish catalog includes menu ' + field + ': ' + key)
  }
}
pass('Spanish catalog covers every static menu string')

const qmlFiles = []
function collectQml(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name)
    if (entry.isDirectory()) collectQml(fullPath)
    else if (entry.isFile() && entry.name.endsWith('.qml')) qmlFiles.push(fullPath)
  }
}
collectQml(path.join(root, 'shell'))
for (const file of qmlFiles) {
  const source = fs.readFileSync(file, 'utf8')
  for (const match of source.matchAll(/I18n\.tr\("((?:[^"\\]|\\.)*)"/g)) {
    const key = JSON.parse('"' + match[1] + '"')
    assert(Object.prototype.hasOwnProperty.call(catalog, key), 'Spanish catalog includes: ' + key + ' (' + path.relative(root, file) + ')')
  }
}
pass('Spanish catalog covers every static QML translation key')
JS

grep -q '^singleton I18n 1.0 I18n.qml$' "$ROOT/shell/Commons/qmldir" || fail "I18n singleton is exported"
pass "I18n singleton is exported"

translated=$(LANGUAGE=es LANG=es_AR.UTF-8 OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_t "Ready to update?"')
[[ $translated == "¿Listo para actualizar?" ]] || fail "Bash helper translates Spanish UI text" "actual: $translated"
pass "Bash helper translates Spanish UI text"

translated=$(LANGUAGE=es LANG=es_AR.UTF-8 OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_t "Remove %1 orphaned package(s)?" 3')
[[ $translated == "¿Eliminar 3 paquetes huérfanos?" ]] || fail "Bash helper interpolates translation arguments" "actual: $translated"
pass "Bash helper interpolates translation arguments"

source_text=$(LANGUAGE=en LANG=en_US.UTF-8 OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_t "Ready to update?"')
[[ $source_text == "Ready to update?" ]] || fail "Bash helper preserves source text outside Spanish" "actual: $source_text"
pass "Bash helper preserves source text outside Spanish"

grep -q 'Qt.locale().toString' "$ROOT/shell/plugins/panels/clock/BarWidget.qml" || fail "clock formats with the active locale"
pass "clock formats with the active locale"
