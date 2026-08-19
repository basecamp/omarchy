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
JS

grep -q '^singleton I18n 1.0 I18n.qml$' "$ROOT/shell/Commons/qmldir" || fail "I18n singleton is exported"
pass "I18n singleton is exported"

grep -q 'Qt.locale().toString' "$ROOT/shell/plugins/panels/clock/BarWidget.qml" || fail "clock formats with the active locale"
pass "clock formats with the active locale"
