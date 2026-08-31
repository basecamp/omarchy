#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')
const source = fs.readFileSync(path.join(root, 'native/plugin-runtime/shell/SecureSurfacePolicy.js'), 'utf8')
const policy = { String, Array }
vm.createContext(policy)
vm.runInContext(source, policy)

const entries = [
  { id: 'v2.status', section: 'right' },
  { id: 'v2.pet', section: 'right' }
]
let screens = ['DP-1', 'DP-2']
let owner = policy.chooseOwner(screens, 'DP-2', '', entries.length > 0)
assertEqual(owner, 'DP-2', 'secure bar initially chooses the focused live monitor')
owner = policy.chooseOwner(screens, 'DP-1', owner, true)
assertEqual(owner, 'DP-2', 'focus changes do not churn a live secure bar owner')

screens = ['DP-1']
owner = policy.chooseOwner(screens, 'DP-1', owner, true)
assertEqual(owner, 'DP-1', 'owner removal fails over to the remaining live monitor')
assertEqual(policy.chooseOpenScreen(['DP-1', 'DP-2'], 'DP-2'), 'DP-2',
  'closed surface opens on the focused live monitor')
assertEqual(policy.chooseOpenScreen(['DP-1'], 'missing'), 'DP-1',
  'closed surface falls back to the first live monitor')
assertEqual(policy.chooseOpenScreen([], 'missing'), '',
  'closed surface fails closed when no monitor is live')
JS
