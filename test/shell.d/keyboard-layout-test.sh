#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const model = requireFromRoot('shell/plugins/bar/widgets/KeyboardLayoutModel.js')

// Trimmed from xkbcli list, keeping the format of every section it prints.
const listing = [
  'models:',
  "- name: 'pc105'",
  '  vendor: Generic',
  '  description: Generic 105-key PC',
  'layouts:',
  "- layout: 'us'",
  "  variant: ''",
  "  brief: 'en'",
  '  description: English (US)',
  "  iso639: ['eng']",
  "  iso3166: ['USA']",
  "- layout: 'us'",
  "  variant: 'intl'",
  "  brief: 'en'",
  '  description: English (US, intl., with dead keys)',
  "- layout: 'br'",
  "  variant: ''",
  "  brief: 'pt'",
  '  description: Portuguese (Brazil)',
  "- layout: 'epo'",
  "  variant: ''",
  "  brief: 'eo'",
  '  description: Esperanto',
  "- layout: 'latam'",
  "  variant: ''",
  "  brief: 'es'",
  '  description: Spanish (Latin American)',
  "- layout: 'mm'",
  "  variant: 'zawgyi'",
  "  brief: 'my-zwg'",
  '  description: Burmese (Zawgyi)',
  'option_groups:',
  "- name: 'grp'",
  '  description: Switching to another layout',
].join('\n')

const briefs = model.layoutBriefs(listing)

assertEqual(briefs['English (US)'], 'en', 'the table reads a layout brief')
assertEqual(briefs['English (US, intl., with dead keys)'], 'en', 'the table reads a variant brief')
assertEqual(briefs['Generic 105-key PC'], undefined, 'the table skips keyboard models')
assertEqual(briefs['Switching to another layout'], undefined, 'the table skips option groups')

assertEqual(model.shortLabel('English (US)', briefs), 'EN', 'the label is the language, not the country')
assertEqual(model.shortLabel('Portuguese (Brazil)', briefs), 'PT', 'a country variant keeps its language')
assertEqual(model.shortLabel('Esperanto', briefs), 'EO', 'a layout without a country still gets a code')
assertEqual(model.shortLabel('Spanish (Latin American)', briefs), 'ES', 'a layout spanning countries still gets a code')
assertEqual(model.shortLabel('Burmese (Zawgyi)', briefs), 'MY', 'a brief carrying a script drops it')
assertEqual(model.shortLabel('A user-defined custom Layout', { 'A user-defined custom Layout': 'custom' }), 'CUS', 'a brief that is a word is cut to size')

assertEqual(model.shortLabel('Elvish (Tengwar)', briefs), 'ELV', 'an unlisted layout falls back to its description')
assertEqual(model.shortLabel('English (US)', {}), 'ENG', 'the label survives an empty table')
assertEqual(model.shortLabel('', briefs), '', 'no keymap means no label')
JS
