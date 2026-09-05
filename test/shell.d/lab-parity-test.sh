#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
run_node_test <<'JS'
const fs = require('fs')
const os = require('os')
const {pathToFileURL} = require('url')
;(async () => {
  const {check} = await import(pathToFileURL(path.join(root, 'test/lab-parity.mjs')))
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'lab-parity-'))
  const native = path.join(fixture, 'native'), standalone = path.join(fixture, 'standalone')
  const log = console.log, error = console.error
  try {
    for (const dir of [native, standalone]) {
      fs.mkdirSync(path.join(dir, 'bin'), {recursive: true})
      fs.mkdirSync(path.join(dir, 'default/lab-vm'), {recursive: true})
      fs.mkdirSync(path.join(dir, 'test'), {recursive: true})
      fs.writeFileSync(path.join(dir, 'bin/omarchy-lab-test'), 'echo shared\n')
      fs.writeFileSync(path.join(dir, 'test/lab-parity.mjs'), 'same checker')
      fs.writeFileSync(path.join(dir, 'test/lab-packaging.json'), 'same adapters')
    }
    fs.mkdirSync(path.join(native, 'shell/plugins/panels/lab'), {recursive: true})
    fs.writeFileSync(path.join(native, 'shell/plugins/panels/lab/manifest.json'), '{}')
    fs.writeFileSync(path.join(standalone, 'manifest.json'), '{}')
    for (const file of ['Panel.qml', 'BarWidget.qml', 'Model.js']) {
      fs.writeFileSync(path.join(native, 'shell/plugins/panels/lab', file), 'shared UI\n')
      fs.writeFileSync(path.join(standalone, file), 'shared UI\n')
    }
    console.log = () => {}
    console.error = () => {}
    const same = check(native, standalone)
    fs.writeFileSync(path.join(standalone, 'Panel.qml'), 'changed UI\n')
    const changed = check(native, standalone)
    fs.writeFileSync(path.join(standalone, 'Panel.qml'), 'shared UI\n')
    fs.writeFileSync(path.join(standalone, 'bin/omarchy-lab-extra'), 'new command\n')
    const missing = check(native, standalone)
    fs.unlinkSync(path.join(standalone, 'bin/omarchy-lab-extra'))
    for (const dir of [native, standalone]) fs.writeFileSync(path.join(dir, 'bin/omarchy-lab-vm'), 'unreviewed adapter')
    const adapter = check(native, standalone)
    console.log = log
    console.error = error
    assert(same, 'parity accepts matching shared code')
    assert(!changed, 'parity rejects a one-sided UI change')
    assert(!missing, 'parity rejects a command missing from either repository')
    assert(!adapter, 'parity rejects unreviewed changes to packaging adapters')
  } finally {
    console.log = log
    console.error = error
    fs.rmSync(fixture, {recursive: true, force: true})
  }
})().catch(error => { console.error(error); process.exit(1) })
JS
