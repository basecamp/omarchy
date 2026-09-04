#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const model = requireFromRoot('shell/plugins/panels/news/Collections.js')
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
