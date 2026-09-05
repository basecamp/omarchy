#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const model = requireFromRoot('shell/plugins/panels/news/Collections.js')
const curated = [{ id: 'omarchy', name: 'Omarchy', sourceUrls: ['https://omarchy.org/news/rss.xml'] }]
assertDeepEqual(model.withBuiltIn(model.parse('')), curated, 'new readers always include curated Omarchy')
assertDeepEqual(model.withBuiltIn(model.parse('[]')), curated, 'empty saved settings cannot remove curated Omarchy')
assertDeepEqual(model.withBuiltIn(model.parse('{broken')), curated, 'curated Omarchy survives malformed settings')
const override = [{ id: 'omarchy', name: 'Changed', sourceUrls: ['https://example.com/rss'] }]
assertDeepEqual(model.withBuiltIn(model.parse(JSON.stringify(override))), curated, 'saved settings cannot rename or replace curated Omarchy sources')
assertDeepEqual(model.parse(JSON.stringify([{ id: 'chefs-choice', name: "Chef's Choice", sourceUrls: [] }])), [], 'previous starter collection is replaced by curated Omarchy')
const curatedArticles = model.buildItemIndex([
  { id: 'official', sourceId: 'omarchy', sourceUrl: 'https://omarchy.org/news/rss.xml' },
  { id: 'tech', sourceId: 'hacker-news', sourceUrl: 'https://news.ycombinator.com/rss' }
], model.withBuiltIn([]), 10)
assertDeepEqual(curatedArticles['collection:omarchy'].map(item => item.id), ['official'], 'curated Omarchy excludes unrelated publisher news')
const catalog = [
  { id: 'linux', url: 'https://linux.example/rss', category: 'linux' },
  { id: 'tech', url: 'https://tech.example/rss', category: 'technology' }
]
const subscriptions = [{ id: 'daily', name: 'Daily', sourceUrls: [catalog[0].url] }]
const reloaded = model.parse(JSON.stringify(subscriptions))
assertDeepEqual(model.subscribedIds(catalog, [], reloaded), ['omarchy', 'linux'], 'collection-only feed stays subscribed after reload')
assertDeepEqual(model.visibleSources(catalog, [], []), [], 'collection-only feeds have no individual tabs')
assertDeepEqual(model.subscribedIds(catalog, ['linux', 'tech'], reloaded), ['omarchy', 'linux', 'tech'], 'standalone and collection subscriptions are deduplicated')
assertDeepEqual(model.subscribedIds(catalog, [], []), ['omarchy'], 'removing the final collection stops an otherwise disabled feed')
const customSource = { id: 'custom-test', url: 'https://custom.example/rss', category: 'custom' }
assertDeepEqual(model.visibleSources([customSource], [], [customSource.url]), [], 'custom tab can be hidden independently')
assertDeepEqual(model.visibleSources([customSource], [], []), [customSource], 'hidden custom tab can be restored')
const hiddenItems = [{ id: 'story', sourceId: 'linux', sourceUrl: catalog[0].url }]
assertDeepEqual(model.buildItemIndex(hiddenItems, reloaded, 10)['collection:daily'], hiddenItems, 'hiding a tab preserves its collection articles')
assertDeepEqual(model.buildItemIndex(hiddenItems, reloaded, 10).all, hiddenItems, 'All still includes collection-only articles')
const urls = Array.from({ length: 21 }, (_, i) => `https://feed-${i}.example/` + 'x'.repeat(1900))
const groups = Array.from({ length: 8 }, (_, i) => ({ id: `group-${i}`, name: `Group ${i}`, sourceUrls: urls }))
const serialized = JSON.stringify(groups)
assert(serialized.length > 8192, 'persistence fixture exceeds the former destructive truncation boundary')
assertDeepEqual(model.parse(serialized), groups, 'all eight large collections survive serialization and reload')
const service = fs.readFileSync(path.join(root, 'shell/plugins/panels/news/Service.qml'), 'utf8')
assert(!/collectionsSetting:[^\n]*substring/.test(service), 'service passes complete collection JSON to the bounded parser')

const original = [{ id: 'tech', name: 'Tech', sourceUrls: [urls[0]] }]
const emptied = model.replaceSource(original, urls[0], '')
assertDeepEqual(emptied, [{ id: 'tech', name: 'Tech', sourceUrls: [] }], 'removing the final subscription preserves the named collection')
assertDeepEqual(model.parse(JSON.stringify(emptied)), emptied, 'empty collections survive restarting the reader')
assertDeepEqual(original[0].sourceUrls, [urls[0]], 'membership updates do not mutate the original settings')
assertDeepEqual(model.replaceSource(groups.slice(0, 1), urls[0], urls[1])[0].sourceUrls, urls.slice(1), 'URL replacement deduplicates collection membership')

const reserved = [{ id: 'constructor', name: 'Constructor', sourceUrls: [] }, { id: '__proto__', name: 'Prototype', sourceUrls: [] }]
assertDeepEqual(model.parse(JSON.stringify(reserved)), reserved, 'valid IDs cannot collide with inherited JavaScript properties')
const index = model.buildItemIndex([{ id: 'a', sourceId: 'constructor', sourceUrl: urls[0] }], [], 10)
assertEqual(index.constructor.length, 1, 'source indexing safely handles reserved object keys')
assertDeepEqual(model.parse(' '.repeat(3 * 1024 * 1024 + 1)), [], 'oversized settings are rejected before parsing')
JS
