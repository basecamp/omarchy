#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

for (const plugin of ['speedtest', 'disk-speedtest']) {
  const manifestPath = path.join(root, 'shell/plugins/panels', plugin, 'manifest.json')
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  assertEqual(manifest.keepLoaded, true, `${manifest.id} stays loaded during process cleanup`)
}
JS
