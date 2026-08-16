#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const model = requireFromRoot('shell/plugins/bar/widgets/KeyboardLayoutModel.js')

// Trimmed from xkbcli list, keeping the format of every section it prints,
// including the options nested under an option group: those quote their
// description and print an empty brief, one indent deeper than a layout's.
const listing = [
  'models:',
  '- name: pc105',
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
  '  allows_multiple: true',
  '  options:',
  "  - name: 'grp:switch'",
  "    brief: ''",
  "    description: 'Right Alt (while pressed)'",
  '    layout-specific: false',
].join('\n')

const briefs = model.layoutBriefs(listing)

assertEqual(briefs['English (US)'], 'en', 'the table reads a layout brief')
assertEqual(briefs['English (US, intl., with dead keys)'], 'en', 'the table reads a variant brief')
assertEqual(briefs['Generic 105-key PC'], undefined, 'the table skips keyboard models')
assertEqual(briefs['Switching to another layout'], undefined, 'the table skips option groups')
assertEqual(briefs["'Right Alt (while pressed)'"], undefined, 'the table skips the options under a group')
assertEqual(Object.keys(briefs).length, 6, 'the table holds nothing but the layouts')

assertEqual(model.shortLabel('English (US)', briefs), 'EN', 'the label is the language, not the country')
assertEqual(model.shortLabel('Portuguese (Brazil)', briefs), 'PT', 'a country variant keeps its language')
assertEqual(model.shortLabel('Esperanto', briefs), 'EO', 'a layout without a country still gets a code')
assertEqual(model.shortLabel('Spanish (Latin American)', briefs), 'ES', 'a layout spanning countries still gets a code')
assertEqual(model.shortLabel('Burmese (Zawgyi)', briefs), 'MY', 'a brief carrying a script drops it')
assertEqual(model.shortLabel('A user-defined custom Layout', { 'A user-defined custom Layout': 'custom' }), 'CUS', 'a brief that is a word is cut to size')

// A brief pairs with the description printed under it, so a block that prints
// one without the other must not hand its code to the block that follows.
const orphaned = model.layoutBriefs([
  'layouts:',
  "- layout: 'us'",
  "  brief: 'en'",
  "- layout: 'gr'",
  '  description: Greek',
].join('\n'))

assertEqual(orphaned['Greek'], undefined, 'a brief stops at the end of its block')

assertEqual(model.shortLabel('Elvish (Tengwar)', briefs), 'ELV', 'an unlisted layout falls back to its description')
assertEqual(model.shortLabel('English (US)', {}), 'ENG', 'the label survives an empty table')
assertEqual(model.shortLabel('constructor', {}), 'CON', 'a description naming a built-in still falls back')
assertEqual(model.shortLabel('', briefs), '', 'no keymap means no label')

// The seat as hyprctl reports it, virtual keyboards already filtered out: the
// buttons libinput calls keyboards sit beside the one being typed on, and the
// main flag lands on either, or on the virtual keyboard that isn't here.
const seat = (activeIndex, main) => [
  { name: 'power-button', active_layout_index: 0, active_keymap: 'English (US)', main: main === 'power-button' },
  { name: 'at-translated-set-2-keyboard', active_layout_index: activeIndex, active_keymap: activeIndex ? 'French' : 'English (US)', main: main === 'keyboard' },
]

assertEqual(model.selectKeyboard(seat(1)).active_keymap, 'French', 'the keyboard that switched is read when nothing holds main')
assertEqual(model.selectKeyboard(seat(1, 'power-button')).active_keymap, 'French', 'the keyboard that switched outranks a button holding main')
assertEqual(model.selectKeyboard(seat(0)).active_keymap, 'English (US)', 'before a switch every keyboard reads the same layout')
assertEqual(model.selectKeyboard(seat(0), 'at-translated-set-2-keyboard').name, 'at-translated-set-2-keyboard', 'the keyboard activelayout named is kept once it switches back')
assertEqual(model.selectKeyboard([{ name: 'a' }, { name: 'b' }]).name, 'a', 'a keyboard reporting no index still gets picked')
assertEqual(model.selectKeyboard([]), undefined, 'a seat with no typed keyboard picks none')

// Two real keyboards on the layout the seat started on, so nothing but the name
// says which one is being typed on. The one that wrapped from the last layout
// back to the first sits behind the other and is still the one that switched.
const pair = (activeIndex, otherIndex) => [
  { name: 'at-translated-set-2-keyboard', active_layout_index: otherIndex, active_keymap: otherIndex ? 'German' : 'English (US)' },
  { name: 'usb-keyboard', active_layout_index: activeIndex, active_keymap: activeIndex ? 'German' : 'English (US)' },
]

assertEqual(model.selectKeyboard(pair(0, 0), 'usb-keyboard').name, 'usb-keyboard', 'the keyboard that switched is read once it is named')
assertEqual(model.selectKeyboard(pair(0, 2), 'usb-keyboard').name, 'usb-keyboard', 'a keyboard that wrapped back to the first layout is still the one that switched')
assertEqual(model.selectKeyboard(pair(0, 2), 'gone-keyboard').name, 'at-translated-set-2-keyboard', 'a name no keyboard answers to falls back to layout progress')

// Hyprland calls the ACPI buttons keyboards too, and hands them the seat's
// layout list. Reading one would describe a layout nobody typed, and switching
// one would leave the keyboard where it was.
assertEqual(model.isTypedKeyboard('at-translated-set-2-keyboard'), true, 'a real keyboard is typed on')
assertEqual(model.isTypedKeyboard('power-button'), false, 'a power button is not')
assertEqual(model.isTypedKeyboard('lid-switch'), false, 'a lid switch is not')
assertEqual(model.isTypedKeyboard('sleep-button'), false, 'a sleep button is not')
assertEqual(model.isTypedKeyboard('hl-virtual-keyboard-1'), false, 'the keyboard an input method injects through is not')
assertEqual(model.isTypedKeyboard(''), true, 'a keyboard reporting no name is left where it was found')

// The activelayout event names the keyboard ahead of the layout it moved to,
// and a description with a comma in it has to survive the split.
const rawEvent = data => ({ data })
const parsedEvent = data => ({ data, parse: count => data.split(',', count - 1).concat(data.split(',').slice(count - 1).join(',')) })

assertEqual(model.eventKeyboardName(rawEvent('at-translated-set-2-keyboard,French')), 'at-translated-set-2-keyboard', 'the event names its keyboard')
assertEqual(model.eventKeyboardName(parsedEvent('at-translated-set-2-keyboard,English (US, intl.)')), 'at-translated-set-2-keyboard', 'a description carrying a comma leaves the name alone')
assertEqual(model.eventKeyboardName(rawEvent('hl-virtual-keyboard,English (US)')), '', 'the keyboard an input method injects through is not typed on')
assertEqual(model.eventKeyboardName({ parse: () => { throw new Error('unsupported') }, data: 'kb,French' }), 'kb', 'a binding without parse falls back to the raw data')
assertEqual(model.eventKeyboardName({}), '', 'an event with nothing in it names no keyboard')
JS
