#!/bin/bash

# Regression coverage for the greeter's session auto-selection

source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const source = fs
  .readFileSync(path.join(root, 'default/sddm/omarchy/resolve-session-index.js'), 'utf8')
  .replace(/^\.pragma library\n/, '')
const sandbox = {}
vm.createContext(sandbox)
vm.runInContext(source, sandbox)

const FILE_ROLE = 258
const DISPLAY_ROLE = 0

function mockSessionModel(lastIndex, files) {
  return {
    lastIndex,
    rowCount: () => files.length,
    index: (row, _column) => row,
    data: (idx, role) => (role === FILE_ROLE ? files[idx] : undefined),
  }
}

const sessions = [
  '/usr/share/wayland-sessions/gnome.desktop',
  '/usr/share/wayland-sessions/hyprland-uwsm.desktop',
  '/usr/share/wayland-sessions/hyprland.desktop',
  '/usr/share/wayland-sessions/omarchy.desktop',
  '/usr/share/wayland-sessions/plasma.desktop',
]

assertEqual(
  sandbox.resolveSessionIndex(mockSessionModel(0, sessions), FILE_ROLE),
  3,
  'selects omarchy.desktop over the hyprland-uwsm.desktop that sorts ahead of it'
)

assertEqual(
  sandbox.resolveSessionIndex(mockSessionModel(0, sessions), DISPLAY_ROLE),
  0,
  'querying Qt.DisplayRole instead of FileRole matches nothing, as it does on real SDDM'
)

assertEqual(
  sandbox.resolveSessionIndex(mockSessionModel(1, sessions.filter((s) => !s.endsWith('omarchy.desktop'))), FILE_ROLE),
  1,
  'keeps the recorded last session when no Omarchy session is installed'
)

assertEqual(
  sandbox.resolveSessionIndex(mockSessionModel(0, []), FILE_ROLE),
  0,
  'stays on the recorded index rather than crashing when the model is empty'
)
JS
