#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

install_usage=$("$ROOT/bin/omarchy-install-dev-env" 2>&1) && fail "install-dev-env requires an environment" || true
[[ $install_usage == *firebase* ]] || fail "install-dev-env usage lists firebase" "$install_usage"
pass "install-dev-env usage lists firebase"

remove_usage=$("$ROOT/bin/omarchy-remove-dev-env" 2>&1) && fail "remove-dev-env requires an environment" || true
[[ $remove_usage == *firebase* ]] || fail "remove-dev-env usage lists firebase" "$remove_usage"
pass "remove-dev-env usage lists firebase"

grep -q 'https://firebase.tools/bin/linux/latest' "$ROOT/bin/omarchy-install-dev-env" || fail "install-dev-env downloads the official Firebase CLI binary"
pass "install-dev-env downloads the official Firebase CLI binary"

grep -q 'rm -f "$HOME/.local/bin/firebase"' "$ROOT/bin/omarchy-remove-dev-env" || fail "remove-dev-env deletes the Firebase CLI binary"
pass "remove-dev-env deletes the Firebase CLI binary"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const parsed = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const byId = Object.fromEntries(parsed.map(item => [item.id, item]))

const install = byId['install.development.firebase']
assert(install, 'menu includes Install > Development > Firebase')
assertEqual(install.label, 'Firebase', 'Firebase install row is labeled Firebase')
assertEqual(install.icon, '', 'Firebase install row uses the Nerd Font Firebase glyph')
assertEqual(install.disabled, '[[ -x $HOME/.local/bin/firebase ]]', 'Firebase install row dims once the CLI is present')
assert(!install.when, 'Firebase install row stays in the catalog after install')
assert(
  install.action.includes("omarchy-install-dev-env firebase"),
  'Firebase install row runs omarchy-install-dev-env firebase'
)

const remove = byId['remove.development.firebase']
assert(remove, 'menu includes Remove > Development > Firebase')
assertEqual(remove.label, 'Firebase', 'Firebase remove row is labeled Firebase')
assertEqual(remove.when, '[[ -x $HOME/.local/bin/firebase ]]', 'Firebase remove row is hidden until the CLI is present')
assert(!remove.disabled, 'Firebase remove row is not dimmed')
assert(
  remove.action.includes("omarchy-remove-dev-env firebase"),
  'Firebase remove row runs omarchy-remove-dev-env firebase'
)
JS
