#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const picker = requireFromRoot('shell/plugins/image-picker/ImagePickerModel.js')

assertEqual(picker.nameForPath('/themes/nord-river.png'), 'nord-river', 'image picker strips directory and extension')
assertEqual(picker.labelForPath('/themes/nord_river.png'), 'Nord River', 'image picker builds display labels')

const rows = [
  '/themes/a/nord-river.png\t/cache/nord-river.jpg',
  '/themes/b/nord-river.png\t/cache/duplicate.jpg',
  '/themes/a/gruvbox-dark.jpeg',
  '',
  '\t/cache/no-path.jpg',
  '/themes/a/plain'
].join('\n')

const images = picker.loadRows(rows)
assertDeepEqual(
  images,
  [
    { filePath: '/themes/a/nord-river.png', fileName: 'nord-river.png', thumbnailPath: '/cache/nord-river.jpg' },
    { filePath: '/themes/a/gruvbox-dark.jpeg', fileName: 'gruvbox-dark.jpeg', thumbnailPath: '/themes/a/gruvbox-dark.jpeg' },
    { filePath: '/themes/a/plain', fileName: 'plain', thumbnailPath: '/themes/a/plain' }
  ],
  'image picker parses rows and dedupes by file name'
)

assert(picker.itemMatches(images, 0, 'river'), 'image picker matches file names')
assert(picker.itemMatches(images, 1, 'Gruvbox Dark'), 'image picker matches labels case-insensitively')
assert(!picker.itemMatches(images, 2, 'river'), 'image picker rejects non-matching filters')
assertEqual(picker.firstMatchingIndex(images, 'plain'), 2, 'image picker finds first matching index')
assertEqual(picker.indexForSelectedImage(images, '/themes/a/gruvbox-dark.jpeg'), 1, 'image picker finds selected image')
assertEqual(picker.indexForSelectedImage(images, '/missing.png'), 0, 'image picker defaults selected image to first row')

assertEqual(picker.filteredPosition(images, 2, 'dark'), 1, 'image picker computes filtered position')
assertEqual(picker.selectedFilteredPosition(images, 2, 'dark'), 0, 'image picker selected filtered position falls back when selected is hidden')
assertEqual(picker.nextSelectedIndexForFilter(images, 0, 'dark'), 1, 'image picker moves selection to first match when filter hides current item')
JS
