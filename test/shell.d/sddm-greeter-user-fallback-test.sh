#!/bin/bash

# Regression coverage for #7949

source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const source = fs
  .readFileSync(path.join(root, 'default/sddm/omarchy/resolve-current-user.js'), 'utf8')
  .replace(/^\.pragma library\n/, '')
const sandbox = {}
vm.createContext(sandbox)
vm.runInContext(source, sandbox)

const DISPLAY_ROLE = 0

function mockUserModel(lastUser, users) {
  return {
    lastUser,
    rowCount: () => users.length,
    index: (row, _column) => row,
    data: (idx, _role) => users[idx],
  }
}

assertEqual(
  sandbox.resolveCurrentUser(mockUserModel('alice', ['alice']), DISPLAY_ROLE),
  'alice',
  'uses the recorded last user when state.conf has one'
)

assertEqual(
  sandbox.resolveCurrentUser(mockUserModel('', ['alice']), DISPLAY_ROLE),
  'alice',
  'falls back to the sole account when lastUser is empty (#7949)'
)

assertEqual(
  sandbox.resolveCurrentUser(mockUserModel('', ['alice', 'bob']), DISPLAY_ROLE),
  '',
  'does not guess a user when lastUser is empty and multiple accounts exist'
)

assertEqual(
  sandbox.resolveCurrentUser(mockUserModel('', []), DISPLAY_ROLE),
  '',
  'stays empty rather than crashing when the model has no accounts at all'
)
JS
