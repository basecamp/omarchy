#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Optional Install rows hide when this architecture's repositories cannot
# satisfy them. The manifest names the complete transaction per menu id, the
# row's `when:` asks omarchy-install-available about it, and the aarch64
# baseline pins which transactions a port is expected to keep resolvable.
run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const byId = new Map(items.map(item => [item.id, item]))
const lines = fs.readFileSync(path.join(root, 'install/optional-packages.tsv'), 'utf8')
  .split('\n')
  .filter(line => line.startsWith('install.'))
const transactions = new Map(lines.map(line => {
  const separator = line.indexOf('|')
  return [line.slice(0, separator), line.slice(separator + 1).split(/\s+/)]
}))
const aurLines = fs.readFileSync(path.join(root, 'install/optional-aur-packages.tsv'), 'utf8')
  .split('\n')
  .filter(line => line.startsWith('install.'))
const aurTransactions = new Map(aurLines.map(line => line.split('|')))
const requiredLines = fs.readFileSync(path.join(root, 'install/optional-packages-aarch64-required'), 'utf8')
  .split('\n')
  .filter(line => line.startsWith('install.'))
const required = new Set(requiredLines)

assertEqual(transactions.size, lines.length, 'optional package transaction ids are unique')
assertEqual(aurTransactions.size, aurLines.length, 'optional AUR transaction ids are unique')
assertEqual(required.size, requiredLines.length, 'required aarch64 transaction ids are unique')
assertEqual(required.size, 20, 'aarch64 support baseline covers every currently supported transaction')
assertDeepEqual(
  [...required].filter(id => !transactions.has(id)),
  [],
  'required aarch64 transactions exist in the package manifest'
)

// The availability check comes first in the guard so a row with nothing to
// install on this architecture never reaches the presence question after it.
for (const [id, packages] of transactions) {
  const item = byId.get(id)
  assert(item, `optional package transaction has a menu row: ${id}`)
  assert(
    (item.when || '').startsWith(`omarchy-install-available ${id}`),
    `optional package transaction guards its menu row: ${id}`
  )
  assert(packages.length > 0 && packages.every(packageName => /^[a-zA-Z0-9@._+:-]+$/.test(packageName)),
    `optional package transaction contains valid names: ${id}`)
}

const unknownGuards = items
  .filter(item => /omarchy-install-available /.test(item.when || ''))
  .filter(item => !transactions.has(item.id))
  .map(item => item.id)
assertDeepEqual(unknownGuards, [], 'optional install guards all have a transaction')

// An AUR build is not a sync package, so the row keeps its plain presence
// check rather than asking the repositories about it. The installer may call
// either helper: what matters is that it names the package the manifest does.
for (const [id, packageName] of aurTransactions) {
  assert(byId.has(id), `optional AUR transaction has a menu row: ${id}`)
  assert(!transactions.has(id), `optional AUR transaction is not treated as a sync package: ${id}`)
  assert(!/omarchy-install-available /.test(byId.get(id).when || ''),
    `optional AUR transaction leaves its row unguarded by the sync database: ${id}`)
  const installer = byId.get(id).action.match(/omarchy-install-[a-z0-9-]+/)[0]
  assert(new RegExp(`\\bomarchy-pkg-(aur-)?add ${packageName}\\b`).test(
    fs.readFileSync(path.join(root, 'bin', installer), 'utf8')
  ), `optional AUR transaction matches its installer: ${id}`)
}

// Install rows dim on package presence, so any row asking that question
// installs a package and has to say which ones.
const unguarded = items
  .filter(item => item.id.startsWith('install.'))
  .filter(item => /omarchy-pkg-present /.test(item.disabled || ''))
  .filter(item => !aurTransactions.has(item.id))
  .filter(item => !transactions.has(item.id))
  .map(item => item.id)
assertDeepEqual(unguarded, [], 'pacman-backed install rows declare complete transactions')

// The secondary packages are the ones a port loses first, and the ones a
// presence check on the primary package would never notice.
const requiredSecondaryPackages = {
  'install.service.1password': ['1password-cli'],
  'install.service.dropbox': ['dropbox-cli', 'libappindicator-gtk3', 'python-gpgme', 'nautilus-dropbox'],
  'install.service.bitwarden': ['bitwarden-cli'],
  'install.ai.dictation': ['wtype'],
  'install.gaming.retroarch': ['libretro-blastem', 'libretro-ppsspp', 'libretro-fbneo-git', 'retroarch-joypad-autoconfig-git'],
  'install.gaming.lutris': ['umu-launcher', 'wine-staging', 'wine-mono', 'wine-gecko', 'winetricks', 'python-protobuf'],
  'install.development.php.php': ['composer', 'php-sqlite', 'xdebug'],
  'install.development.php.symfony': ['composer', 'php-sqlite', 'xdebug', 'symfony-cli']
}
for (const [id, expected] of Object.entries(requiredSecondaryPackages)) {
  assertDeepEqual(
    expected.filter(packageName => !transactions.get(id).includes(packageName)),
    [],
    `optional package transaction includes secondary packages: ${id}`
  )
}
JS

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/omarchy/install" "$test_tmp/bin"
printf '%s\n' 'install.example|primary secondary' >"$test_tmp/omarchy/install/optional-packages.tsv"

cat >"$test_tmp/bin/omarchy-pkg-available" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_LOG"
[[ $* == 'primary secondary' ]]
SH
chmod +x "$test_tmp/bin/omarchy-pkg-available"

export OMARCHY_TEST_LOG="$test_tmp/packages.log"
OMARCHY_PATH="$test_tmp/omarchy" PATH="$test_tmp/bin:$PATH" "$ROOT/bin/omarchy-install-available" install.example
[[ $(<"$OMARCHY_TEST_LOG") == 'primary secondary' ]] || fail 'optional install availability checks the complete transaction'
pass 'optional install availability checks the complete transaction'

if OMARCHY_PATH="$test_tmp/omarchy" PATH="$test_tmp/bin:$PATH" "$ROOT/bin/omarchy-install-available" install.unknown 2>/dev/null; then
  fail 'optional install availability rejects unknown transactions'
fi
pass 'optional install availability rejects unknown transactions'

# `pacman -Si` is the question; every name has to answer, and none at all is
# vacuously available, the same way omarchy-pkg-present treats no arguments.
cat >"$test_tmp/bin/pacman" <<'SH'
#!/bin/bash
[[ $1 == -Si ]] || exit 1
shift
for want in "$@"; do
  [[ $want != missing* ]] || exit 1
done
SH
chmod +x "$test_tmp/bin/pacman"

PATH="$test_tmp/bin:$PATH" "$ROOT/bin/omarchy-pkg-available" primary secondary ||
  fail 'package availability accepts names the repositories carry'
PATH="$test_tmp/bin:$PATH" "$ROOT/bin/omarchy-pkg-available" ||
  fail 'package availability is true of no packages at all'
if PATH="$test_tmp/bin:$PATH" "$ROOT/bin/omarchy-pkg-available" primary missing; then
  fail 'package availability fails when any name is absent from the repositories'
fi
pass 'package availability asks the sync database about every name'
