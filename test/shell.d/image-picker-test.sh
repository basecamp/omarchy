#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
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
    {
      filePath: '/themes/a/nord-river.png',
      fileName: 'nord-river.png',
      thumbnailPath: '/cache/nord-river.jpg',
      group: '',
      variants: [{ filePath: '/themes/a/nord-river.png', fileName: 'nord-river.png', thumbnailPath: '/cache/nord-river.jpg' }]
    },
    {
      filePath: '/themes/a/gruvbox-dark.jpeg',
      fileName: 'gruvbox-dark.jpeg',
      thumbnailPath: '/themes/a/gruvbox-dark.jpeg',
      group: '',
      variants: [{ filePath: '/themes/a/gruvbox-dark.jpeg', fileName: 'gruvbox-dark.jpeg', thumbnailPath: '/themes/a/gruvbox-dark.jpeg' }]
    },
    {
      filePath: '/themes/a/plain',
      fileName: 'plain',
      thumbnailPath: '/themes/a/plain',
      group: '',
      variants: [{ filePath: '/themes/a/plain', fileName: 'plain', thumbnailPath: '/themes/a/plain' }]
    }
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

assertEqual(picker.variantCount(images, 0), 1, 'an ungrouped row is a single variant')
assertEqual(picker.maxVariantCount(images), 1, 'ungrouped rows never carry variants')

// A third column groups rows into one carousel item: the theme picker hands one
// group per theme, carrying that theme's preview and every background it ships.
const groupedRows = [
  '/previews/nord/000-preview.png\t/cache/nord-preview.jpg\tnord',
  '/previews/nord/001-city.webp\t/cache/nord-city.jpg\tnord',
  '/previews/nord/002-moon.jpg\t/cache/nord-moon.jpg\tnord',
  '/previews/nord/002-moon.jpg\t/cache/duplicate.jpg\tnord',
  '/previews/rose-pine/000-preview.png\t/cache/rose-preview.jpg\trose-pine',
  '/previews/rose-pine/001-city.webp\t/cache/rose-city.jpg\trose-pine'
].join('\n')

const grouped = picker.loadRows(groupedRows)
assertEqual(grouped.length, 2, 'grouped rows collapse into one item per group')
assertEqual(picker.variantCount(grouped, 0), 3, 'a group carries every row as a variant')
assertEqual(grouped[0].filePath, '/previews/nord/000-preview.png', 'a grouped item leads with its first row')
assertEqual(
  grouped[1].variants[1].filePath,
  '/previews/rose-pine/001-city.webp',
  'the same file name in two groups is kept in both'
)

assertEqual(picker.variantAt(grouped, 0, 1).thumbnailPath, '/cache/nord-city.jpg', 'variants resolve to their own thumbnail')
assertEqual(picker.variantAt(grouped, 0, 3).filePath, '/previews/nord/000-preview.png', 'variant lookup wraps forward')
assertEqual(picker.variantAt(grouped, 0, -1).filePath, '/previews/nord/002-moon.jpg', 'variant lookup wraps backward')
assertEqual(picker.maxVariantCount(grouped), 3, 'the widest group decides whether the carousel makes room to peek')

assertEqual(picker.nameForItem(grouped, 1), 'rose-pine', 'a grouped item is named for its group')
assertEqual(picker.labelForItem(grouped, 1), 'Rose Pine', 'a grouped item is labelled for its group')
assertEqual(picker.labelForItem(images, 0), 'Nord River', 'an ungrouped item is still labelled for its file')
assert(picker.itemMatches(grouped, 1, 'rose'), 'filtering a grouped item matches the group, not the variant file')
assert(!picker.itemMatches(grouped, 1, 'city'), 'filtering a grouped item ignores its variant file names')

assertDeepEqual(
  picker.locateImage(grouped, '/previews/rose-pine/001-city.webp'),
  { index: 1, variant: 1 },
  'a path locates both its item and its variant'
)
assertDeepEqual(
  picker.locateImage(grouped, '/previews/gone.png'),
  { index: 0, variant: 0 },
  'an unknown path opens the picker on the first item'
)

const imagePickerQml = fs.readFileSync(path.join(root, 'shell/plugins/image-picker/ImagePicker.qml'), 'utf8')
assert(
  /function preloadRows[\s\S]*if \(opened \|\| requestActive\) return/.test(imagePickerQml),
  'image picker ignores cache preloads while a request is visible'
)
const skewedImageQml = fs.readFileSync(path.join(root, 'shell/plugins/image-picker/SkewedImage.qml'), 'utf8')
assert(
  /source: item\.sourceActivated \? item\.thumbnailPath : ""/.test(imagePickerQml) &&
    /asynchronous: false/.test(skewedImageQml),
  'image picker loads activated thumbnails synchronously to avoid carousel flicker'
)

// The peek bands and the preview have to lean at one angle, which they only do
// while they share a column: their own heights differ by a factor of seven.
assert(
  /columnHeight: item\.selected \? root\.columnHeight : item\.height/.test(imagePickerQml) &&
    /skewOffset: item\.selected \? root\.columnSkew : root\.skewOffset/.test(imagePickerQml),
  'the selected preview leans as part of the column it shares with its peek bands'
)
assert(
  /variantPeekHeight: Math\.round\(sliceWidth \* peekScale\)/.test(imagePickerQml) &&
    /variantPeekOverlap: Math\.round\(-sliceSpacing \* peekScale\)/.test(imagePickerQml),
  'the vertical peek is derived from the horizontal slice geometry'
)
assert(
  /hints\.push\("\\u2191 \\u2193" \+ \(variantLabel/.test(imagePickerQml),
  'the arrow hint names the axis the caller gave it'
)
assert(
  /event\.key === Qt\.Key_Up\)\s*\{\s*root\.cycleVariant\(-1\)/.test(imagePickerQml) &&
    /event\.key === Qt\.Key_Down\)\s*\{\s*root\.cycleVariant\(1\)/.test(imagePickerQml),
  'image picker cycles the selected item variants with up and down'
)
assert(
  /selected \? root\.variantThumbnail\(index, root\.selectedVariant\)/.test(imagePickerQml),
  'image picker shows the selected variant in the expanded preview'
)
JS
