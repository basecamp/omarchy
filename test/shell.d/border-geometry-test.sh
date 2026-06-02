#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const source = fs.readFileSync(path.join(root, 'shell/Commons/BorderGeometry.js'), 'utf8').replace(/^\.pragma library\n/, '')
const geometry = {}
vm.createContext(geometry)
vm.runInContext(source, geometry)

assertDeepEqual(
  geometry.parseWidthSpec('2 4 6 8', 1),
  { top: 2, right: 4, bottom: 6, left: 8 },
  'border geometry parses four-sided widths'
)

assertDeepEqual(
  geometry.parseWidthSpec('2 4', 1),
  { top: 2, right: 4, bottom: 2, left: 4 },
  'border geometry parses CSS two-value widths'
)

const gradient = geometry.parseGradientSpec('rgba(010203ee) rgba(040506ee) 45deg', '#336699', 1)
assertEqual(gradient.colors[0], '#010203ee', 'border geometry parses first rgba gradient stop')
assertEqual(gradient.colors[1], '#040506ee', 'border geometry parses second rgba gradient stop')
assertEqual(gradient.angle, 45, 'border geometry parses gradient angle')
assert(gradient.enabled, 'border geometry marks multi-stop gradients enabled')

assertEqual(
  geometry.canonicalColor('0xee33ccff', 1),
  '#33ccffee',
  'border geometry converts legacy ARGB color to QML RGBA hex'
)

const pathData = geometry.ringPath(100, 50, 10, { top: 4, right: 2, bottom: 8, left: 6 })
assert(pathData.includes('M 10 0'), 'border geometry emits outer rounded path')
assert(pathData.includes('M 10 4'), 'border geometry emits inset inner rounded path')

const endpoints = geometry.gradientEndpoints(100, 50, 0)
assertEqual(Math.round(endpoints.x1), 0, 'border geometry 0deg starts at left edge')
assertEqual(Math.round(endpoints.x2), 100, 'border geometry 0deg ends at right edge')
JS
