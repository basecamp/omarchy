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
assertEqual(picker.indexForCursor(images, '/themes/a/gruvbox-dark.jpeg'), 1, 'image picker finds a remote cursor by path')
assertEqual(picker.indexForCursor(images, 'gruvbox-dark.jpeg'), 1, 'image picker finds a remote cursor by file name')
assertEqual(picker.indexForCursor(images, 'gruvbox-dark'), 1, 'image picker finds a remote cursor by name')
assertEqual(picker.indexForCursor(images, 'Gruvbox Dark'), -1, 'image picker cursor matching stays exact')
assertEqual(picker.indexForCursor(images, 'missing'), -1, 'image picker rejects an unknown remote cursor')

assertEqual(picker.filteredPosition(images, 2, 'dark'), 1, 'image picker computes filtered position')
assertEqual(picker.selectedFilteredPosition(images, 2, 'dark'), 0, 'image picker selected filtered position falls back when selected is hidden')
assertEqual(picker.nextSelectedIndexForFilter(images, 0, 'dark'), 1, 'image picker moves selection to first match when filter hides current item')

const imagePickerQml = fs.readFileSync(path.join(root, 'shell/plugins/image-picker/ImagePicker.qml'), 'utf8')
assert(
  /function preloadRows[\s\S]*if \(opened \|\| requestActive\) return/.test(imagePickerQml),
  'image picker ignores cache preloads while a request is visible'
)
assert(
  /source: item\.sourceActivated && item\.thumbnailPath \? Util\.fileUrl\(item\.thumbnailPath\) : ""[\s\S]*asynchronous: false/.test(imagePickerQml),
  'image picker loads activated thumbnails synchronously to avoid carousel flicker'
)
assert(
  /function cursorState\(\)[\s\S]*opened: opened[\s\S]*cursorPath: path[\s\S]*cursorName: path \? nameForPath\(path\) : ""/.test(imagePickerQml),
  'image picker exposes live cursor state'
)
assert(
  /function setCursor\(cursor\)[\s\S]*if \(!opened\) return "closed"[\s\S]*indexForCursor\(imageArray, cursor\)[\s\S]*select\(index, true\)/.test(imagePickerQml),
  'image picker moves a remote cursor without applying it'
)
assert(
  /function applyCursor\(\)[\s\S]*if \(!opened\) return "closed"[\s\S]*applySelected\(\)/.test(imagePickerQml),
  'image picker remote apply reuses the existing selection flow'
)

const shellQml = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')
assert(
  /target: "image-selector"[\s\S]*function state\(\): string[\s\S]*function setCursor\(cursor: string\): string[\s\S]*function apply\(\): string/.test(shellQml),
  'image selector IPC exposes state, setCursor, and apply'
)

const themeSwitcher = fs.readFileSync(path.join(root, 'bin/omarchy-theme-switcher'), 'utf8')
const backgroundSwitcher = fs.readFileSync(path.join(root, 'bin/omarchy-theme-bg-switcher'), 'utf8')
assert(/menu_args=\([\s\S]*--context theme/.test(themeSwitcher), 'theme picker declares its semantic context')
assert(/omarchy-menu-images[\s\S]*--context background/.test(backgroundSwitcher), 'background picker declares its semantic context')
JS
