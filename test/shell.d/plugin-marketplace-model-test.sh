#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const marketplace = requireFromRoot('shell/plugins/plugin-marketplace/MarketplaceModel.js')

const plugins = marketplace.normalize({ plugins: [
  {
    id: 'acme.clock', name: 'Clock', description: 'A focused desktop clock', author: 'Acme', category: 'Widgets', kind: 'Bar widget', tags: ['bar', 'time'], stars: 9, addedAt: '2026-02-01', installAvailable: true, verificationStatus: 'verified',
    previewImages: ['https://plugins.omarchy.org/previews/clock-detail.png', 'https://plugins.omarchy.org/previews/clock-second.png']
  },
  { id: 'acme.menu', name: 'Quick Menu', description: 'Search programs', author: 'Acme', category: 'Menus', kind: 'Overlay', tags: ['launcher'], stars: 2, addedAt: '2026-03-01', installAvailable: false }
]}, ['acme.clock'])

assertEqual(plugins.length, 2, 'marketplace model keeps valid community plugins')
assert(plugins[0].installed && plugins[0].verified, 'marketplace model combines installed and verified state')
assertDeepEqual(plugins[0].previewImages, ['https://plugins.omarchy.org/previews/clock-detail.png', 'https://plugins.omarchy.org/previews/clock-second.png'], 'marketplace model preserves all preview images')
assertDeepEqual(marketplace.options(plugins, 'category'), ['Menus', 'Widgets'], 'marketplace model exposes category filters')
assertEqual(marketplace.filtered(plugins, { query: 'focused desktop', sort: 'relevance' })[0].id, 'acme.clock', 'marketplace model searches descriptions')
assertEqual(marketplace.filtered(plugins, { category: 'Menus' })[0].id, 'acme.menu', 'marketplace model filters category')
assertEqual(marketplace.filtered(plugins, { installable: true })[0].id, 'acme.clock', 'marketplace model filters installable plugins')
assertEqual(marketplace.filtered(plugins, { installed: 'available' })[0].id, 'acme.menu', 'marketplace model filters installed state')
assertEqual(marketplace.filtered(plugins, { sort: 'stars' })[0].id, 'acme.clock', 'marketplace model sorts by stars')
assertDeepEqual(marketplace.badges(plugins[0]), ['Installed', 'Verified'], 'marketplace model labels installed verified plugins')
JS
