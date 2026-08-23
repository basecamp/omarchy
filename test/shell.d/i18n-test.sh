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
assertEqual(i18n.interpolate('%1 / %2', ['A', 'literal %1']), 'A / literal %1', 'argument text is not reinterpreted as a placeholder')
assertEqual(i18n.interpolate('%1 / %3', ['A']), 'A / %3', 'unmatched placeholders are preserved')
assertEqual(i18n.translatePlural(1, '%1 item', '%1 items', { '%1 item': '%1 elemento' }, [1]), '1 elemento', 'singular translation is selected for one')
assertEqual(i18n.translatePlural(2, '%1 item', '%1 items', { '%1 items': '%1 elementos' }, [2]), '2 elementos', 'plural translation is selected for other counts')

const catalog = JSON.parse(fs.readFileSync(path.join(root, 'shell/translations/es.json'), 'utf8'))
assertEqual(catalog['Enter Password'], 'Introduce la contraseña', 'Spanish catalog parses and exposes lock text')

const translationsDirectory = path.join(root, 'shell/translations')
const manifest = JSON.parse(fs.readFileSync(path.join(translationsDirectory, 'catalogs.json'), 'utf8'))
const catalogNames = fs.readdirSync(translationsDirectory)
  .filter(name => name.endsWith('.json') && name !== 'catalogs.json')
  .map(name => name.slice(0, -5))
  .sort()
assertDeepEqual([...manifest].sort(), catalogNames, 'translation manifest lists every catalog exactly once')

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
  const patterns = [
    /I18n\.tr\("((?:[^"\\]|\\.)*)"/g,
    /I18n\.ntr\([^,]+,\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"/g
  ]
  for (const pattern of patterns) {
    for (const match of source.matchAll(pattern)) {
      for (const rawKey of match.slice(1)) {
        const key = JSON.parse('"' + rawKey + '"')
        assert(Object.prototype.hasOwnProperty.call(catalog, key), 'Spanish catalog includes: ' + key + ' (' + path.relative(root, file) + ')')
      }
    }
  }
}
pass('Spanish catalog covers every static QML translation key')

const binFiles = fs.readdirSync(path.join(root, 'bin')).map((name) => path.join(root, 'bin', name))
for (const file of binFiles) {
  if (!fs.statSync(file).isFile()) continue
  const source = fs.readFileSync(file, 'utf8')
  const patterns = [
    /\bomarchy_t "([^"$]*)"/g,
    /\bomarchy_nt\s+(?:"[^"]*"|\S+)\s+(?:\\\s*)?"([^"$]*)"\s+(?:\\\s*)?"([^"$]*)"/g
  ]
  for (const pattern of patterns) {
    for (const match of source.matchAll(pattern)) {
      for (const key of match.slice(1)) {
        assert(Object.prototype.hasOwnProperty.call(catalog, key), 'Spanish catalog includes: ' + key + ' (' + path.relative(root, file) + ')')
      }
    }
  }
}
pass('Spanish catalog covers every static Bash translation key')
JS

grep -q '^singleton I18n 1.0 I18n.qml$' "$ROOT/shell/Commons/qmldir" || fail "I18n singleton is exported"
pass "I18n singleton is exported"

translated=$(LANGUAGE=es LANG=es_AR.UTF-8 OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_t "Ready to update?"')
[[ $translated == "¿Listo para actualizar?" ]] || fail "Bash helper translates Spanish UI text" "actual: $translated"
pass "Bash helper translates Spanish UI text"

translated=$(LANGUAGE=fr_FR:es_AR:en LANG=en_US.UTF-8 OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_t "Ready to update?"')
[[ $translated == "¿Listo para actualizar?" ]] || fail "Bash helper follows the LANGUAGE preference list" "actual: $translated"
pass "Bash helper follows the LANGUAGE preference list"

translated=$(LANGUAGE=es LANG=es_AR.UTF-8 OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_nt 1 "Remove %1 orphaned package?" "Remove %1 orphaned packages?" 1')
[[ $translated == "¿Eliminar 1 paquete huérfano?" ]] || fail "Bash helper translates singular text" "actual: $translated"
pass "Bash helper translates singular text"

translated=$(LANGUAGE=es LANG=es_AR.UTF-8 OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_nt 3 "Remove %1 orphaned package?" "Remove %1 orphaned packages?" 3')
[[ $translated == "¿Eliminar 3 paquetes huérfanos?" ]] || fail "Bash helper translates plural text" "actual: $translated"
pass "Bash helper translates plural text"

translated=$(LANGUAGE=es LANG=es_AR.UTF-8 OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_t "%1 in %2 minutes" "check %2 tasks" 5')
[[ $translated == "check %2 tasks en 5 minutos" ]] ||
  fail "Bash helper does not let one argument's text collide with a later placeholder" "actual: $translated"
pass "Bash helper does not let one argument's text collide with a later placeholder"

translated=$(LANGUAGE=C OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_t "%1 / %2" A "literal %1"')
[[ $translated == "A / literal %1" ]] ||
  fail "Bash helper does not reinterpret argument text as a placeholder" "actual: $translated"
pass "Bash helper does not reinterpret argument text as a placeholder"

translated=$(LANGUAGE=C OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_t "%1 / %3" A')
[[ $translated == "A / %3" ]] || fail "Bash helper preserves unmatched placeholders" "actual: $translated"
pass "Bash helper preserves unmatched placeholders"

source_text=$(LANGUAGE=en LANG=en_US.UTF-8 OMARCHY_PATH="$ROOT" bash -c 'source "$OMARCHY_PATH/default/bash/i18n"; omarchy_t "Ready to update?"')
[[ $source_text == "Ready to update?" ]] || fail "Bash helper preserves source text outside Spanish" "actual: $source_text"
pass "Bash helper preserves source text outside Spanish"

without_jq=$(LANGUAGE=es LANG=es_AR.UTF-8 OMARCHY_PATH="$ROOT" bash -c 'PATH=/nonexistent; source "$OMARCHY_PATH/default/bash/i18n"; omarchy_t "Ready to update?"')
[[ $without_jq == "Ready to update?" ]] || fail "Bash helper falls back to source text when jq is unavailable" "actual: $without_jq"
pass "Bash helper falls back to source text when jq is unavailable"

grep -q 'Qt.locale().toString' "$ROOT/shell/plugins/panels/clock/BarWidget.qml" || fail "clock formats with the active locale"
pass "clock formats with the active locale"
