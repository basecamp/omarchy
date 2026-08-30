#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The primitive must be a no-op on a stock tree: nothing calls it yet.
if matches=$(rg -n 'I18n\.(tr|trc|ntr|domain|noop)\(|\b_\.(tr|trc|ntr)\(' "$ROOT/shell" -g '*.qml' -g '*.js' -g '!I18n.qml' -g '!I18nModel.js'); then
  fail "no shell code calls I18n yet (this change is mechanism only)" "$matches"
fi
pass "no shell code calls I18n yet"

run_node_test <<'JS'
const I18n = requireFromRoot('shell/Commons/I18nModel.js')

// Locale selection
assertEqual(I18n.normalizeLocale('ca_ES.UTF-8'), 'ca_ES', 'locale normalization strips the encoding')
assertEqual(I18n.normalizeLocale('es-ar@latin'), 'es_AR', 'locale normalization canonicalizes separators')
assertEqual(I18n.normalizeLocale('C'), '', 'C locale means no translation')
assertDeepEqual(I18n.localeCandidates({ LANG: 'ca_ES.UTF-8' }), ['ca_ES', 'ca'], 'regional locale falls back to its language')
assertDeepEqual(I18n.localeCandidates({ LANG: 'de_DE', LC_MESSAGES: 'fr_FR' }), ['fr_FR', 'fr'], 'LC_MESSAGES beats LANG')
assertDeepEqual(I18n.localeCandidates({ LANGUAGE: 'ca:es', LANG: 'de_DE' }), ['ca', 'es'], 'LANGUAGE is an ordered preference list')
assertDeepEqual(I18n.localeCandidates({ LANGUAGE: 'fr:en:es' }), ['fr', 'en'], 'nothing after English can apply')

// Interpolation
assertEqual(I18n.interpolate('%1 of %2', ['3', 7]), '3 of 7', 'placeholders are filled by position')
assertEqual(I18n.interpolate('%10 %1', ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j']), 'j a', '%10 is not %1 followed by 0')
assertEqual(I18n.interpolate('%1 in %2 min', ['say %2', 5]), 'say %2 in 5 min', 'an argument containing a placeholder is inserted verbatim')
assertEqual(I18n.interpolate('%1 and %3', ['a']), 'a and %3', 'unmatched placeholders are preserved')

// Plural rules come from the catalog header and are evaluated by a parser, never eval
const pl = I18n.parsePluralForms('nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);')
assertDeepEqual([1, 2, 5, 22, 102].map(pl.plural), [0, 1, 2, 1, 1], 'Polish plural rule selects all three forms')
const ar = I18n.parsePluralForms('nplurals=6; plural=(n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : n%100>=3 && n%100<=10 ? 3 : n%100>=11 ? 4 : 5);')
assertDeepEqual([0, 1, 2, 3, 11, 100].map(ar.plural), [0, 1, 2, 3, 4, 5], 'Arabic plural rule selects all six forms')
assertEqual(I18n.parsePluralForms('nplurals=2; plural=(process.exit(1));'), null, 'a plural rule that is not a C expression is rejected, not evaluated')
assertEqual(I18n.parsePluralForms('nplurals=2; plural=(n ? );'), null, 'a malformed plural rule is rejected whole')

// Resolution: nothing registered, bound, unbound, context
const empty = I18n.createRegistry()
assertEqual(empty.translate('Connect'), 'Connect', 'with nothing registered a lookup returns its source')
assertEqual(empty.translatePlural(3, '%1 city', '%1 cities', { args: [3] }), '3 cities', 'with nothing registered plurals follow English')

const en = { '': { 'plural-forms': 'nplurals=2; plural=(n != 1);' } }
const reg = I18n.createRegistry()
reg.setCatalogs('lang.ca', {
  'omarchy.shell': Object.assign({}, en, { Cancel: 'Cancel·la', Open: 'Obre' }),
  'omarchy.menu': Object.assign({}, en, { Connect: 'Connecta', Open: 'Obre', '%1 city': ['%1 ciutat', '%1 ciutats'], 'verb\u0004Play': 'Reprodueix' }),
  'dev.foo.weather': Object.assign({}, en, { Open: 'Obert' }),
})
assertEqual(reg.translate('Connect', { domain: 'omarchy.menu' }), 'Connecta', 'a bound caller resolves in its own domain')
assertEqual(reg.translate('Open', { domain: 'omarchy.menu' }), 'Obre', 'two bound plugins can translate one word differently (menu)')
assertEqual(reg.translate('Open', { domain: 'dev.foo.weather' }), 'Obert', 'two bound plugins can translate one word differently (weather)')
assertEqual(reg.translate('Cancel', { domain: 'dev.foo.weather' }), 'Cancel·la', 'a bound caller falls through to the global merge')
assertEqual(reg.translate('Connect'), 'Connecta', 'an unbound caller resolves through the global merge')
assertEqual(reg.translate('Play', { domain: 'omarchy.menu', context: 'verb' }), 'Reprodueix', 'msgctxt separates entries')
assertEqual(reg.translate('Play', { domain: 'omarchy.menu' }), 'Play', 'a context-free lookup does not see the contextual entry')
assertEqual(reg.translatePlural(4, '%1 city', '%1 cities', { domain: 'omarchy.menu', args: [4] }), '4 ciutats', 'plurals use the rule from the catalog the key was found in')

// A fallback locale with a different plural rule cannot lend plural entries
const mixed = I18n.createRegistry()
mixed.setCatalogs('lang.pl', { d: { '': { 'plural-forms': 'nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);' },
  '%1 file': ['%1 plik', '%1 pliki', '%1 plików'], Save: 'Zapisz' } }, { precedence: 1 })
mixed.setCatalogs('lang.ca', { d: Object.assign({}, en, { Open: 'Obre' }) }, { precedence: 0 })
assertEqual(mixed.translate('Save', { domain: 'd' }), 'Zapisz', 'a fallback locale lends singular entries the preferred one lacks')
assertEqual(mixed.translatePlural(5, '%1 file', '%1 files', { domain: 'd', args: [5] }), '5 files', 'a fallback locale with another plural rule does not lend plural entries')
assertEqual(mixed.snapshot().catalogs.d['%1 file'], undefined, 'the snapshot Bash reads stays consistent with its one header per domain')

// Names that collide with Object.prototype: PluginRegistry accepts them as ids
// (built with JSON.parse, as a real catalog is: in an object literal
// `__proto__:` would set the prototype instead of creating a key)
const proto = I18n.createRegistry()
proto.setCatalogs('constructor',
  JSON.parse('{"constructor": {"toString": "cadena", "__proto__": "proto", "Open": "Obre"}}'),
  { links: JSON.parse('{"__proto__": "constructor"}') })
assertEqual(proto.translate('Open', { domain: 'constructor' }), 'Obre', 'a plugin id of "constructor" gets a real catalog')
assertEqual(proto.translate('toString', { domain: 'constructor' }), 'cadena', 'a source string of "toString" is an ordinary key')
assertEqual(proto.translate('__proto__', { domain: 'constructor' }), 'proto', 'a source string of "__proto__" is an ordinary key')
assertEqual(Object.prototype.toString.call({}), '[object Object]', 'Object.prototype is untouched')
assertEqual(typeof ({}).constructor, 'function', 'Object.prototype.constructor is untouched')
assertDeepEqual(proto.domains(), ['constructor'], 'the domain list is exactly what was registered')

// Clone chain: own domain, then clonedFrom, then global
const clone = I18n.createRegistry()
clone.setCatalogs('lang.ca', {
  'omarchy.menu': { Connect: 'Connecta', Open: 'Obre', Refresh: 'Actualitza' },
  'my.menu': { Open: 'Obre-ho', Frobnicate: 'Frobnica' },
}, { links: { 'my.menu': 'omarchy.menu' } })
assertEqual(clone.translate('Frobnicate', { domain: 'my.menu' }), 'Frobnica', 'a clone translates strings it added')
assertEqual(clone.translate('Refresh', { domain: 'my.menu' }), 'Actualitza', 'a clone inherits what it did not change')
assertEqual(clone.translate('Open', { domain: 'my.menu' }), 'Obre-ho', 'a clone overrides one upstream translation')
assertEqual(clone.translate('Open', { domain: 'omarchy.menu' }), 'Obre', 'the original is unaffected by the clone')

// Owners are replaced atomically and removed cleanly
const owners = I18n.createRegistry()
owners.setCatalogs('p', { d: { a: '1', b: '2' } })
owners.setCatalogs('p', { d: { a: '9' } })
assertEqual(owners.translate('b', { domain: 'd' }), 'b', 're-registering an owner replaces its whole set')
assertEqual(owners.clearOwner('p'), true, 'an owner can be cleared')
assertEqual(owners.translate('a', { domain: 'd' }), 'a', 'clearing an owner removes its catalogs')

// Startup cache: a stand-in that never outlives a live pack
const first = I18n.createRegistry()
first.setCatalogs('lang.ca', { 'omarchy.menu': { Refresh: 'Actualitza' } })
const login2 = I18n.createRegistry()
assertEqual(login2.loadSnapshot(first.snapshot()), true, 'the cache loads at the next start')
assertEqual(login2.translate('Refresh', { domain: 'omarchy.menu' }), 'Actualitza', 'the cache answers before packs register')
login2.setCatalogs('lang.ca', { 'omarchy.menu': { Refresh: 'Refresca' } })
assertEqual(login2.translate('Refresh', { domain: 'omarchy.menu' }), 'Refresca', 'a live pack overrides the cache')
login2.clearOwner('lang.ca')
assertEqual(login2.translate('Refresh', { domain: 'omarchy.menu' }), 'Refresh', 'disabling the pack reverts to English, the cache does not linger')
assertDeepEqual(login2.snapshot().catalogs, {}, 'the written cache never contains the cache itself')
assertEqual(login2.loadSnapshot(first.snapshot()), false, 'the cache does not reload over live data')
JS
