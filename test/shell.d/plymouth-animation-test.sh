#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The script plugin is an optional native test dependency on headless CI.
if ! command -v cc >/dev/null || ! command -v pkg-config >/dev/null || ! pkg-config --exists ply-splash-core libpng || [[ ! -f ${PLYMOUTH_SCRIPT_PLUGIN:-/usr/lib/plymouth/script.so} ]]; then
  pass "SKIP native Plymouth animation: install Plymouth headers, script plugin, C compiler, and libpng"
  exit 0
fi

ulimit -c 0

run_node_test <<'JS'
const fs = require('node:fs')
const os = require('node:os')
const { execFileSync } = require('node:child_process')
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchy-plymouth-test-'))
const plugin = process.env.PLYMOUTH_SCRIPT_PLUGIN || '/usr/lib/plymouth/script.so'
const assets = path.join(root, 'default/plymouth')
const executable = path.join(scratch, 'render')
let serial = 0

function run(options = {}) {
  const { style = 'dust-drift', duration = '2.4', mode = 'shutdown', frames = 100, scenario = 'normal', imageDir = assets, width = 1280, height = 720 } = options
  const descriptor = path.join(scratch, `theme-${serial++}.plymouth`)
  fs.writeFileSync(descriptor, `[Plymouth Theme]\nName=Test\nModuleName=script\n[script]\nImageDir=${imageDir}\nScriptFile=${assets}/omarchy.script\n[script-env-vars]\n${style === null ? '' : `ShutdownAnimation=${style}\n`}${duration === null ? '' : `ShutdownDuration=${duration}\n`}`)
  const output = execFileSync(executable, [plugin, descriptor, mode, String(frames), '-', scenario, String(width), String(height)], { encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'] })
  return output.trim().split('\n').slice(1).map(line => {
    const [frame, foreground, hash] = line.split(',')
    return { frame: Number(frame), foreground: Number(foreground), hash }
  })
}

function staysStatic(rows) { return rows.every(row => row.hash === rows[0].hash && row.foreground > 0) }
function endsBlank(rows) { return rows.slice(-10).every(row => row.foreground === 0) }
function blankFrame(rows) { return rows.find(row => row.foreground === 0)?.frame }

try {
  const flags = execFileSync('pkg-config', ['--cflags', '--libs', 'ply-splash-core', 'libpng'], { encoding: 'utf8' }).trim().split(/\s+/)
  execFileSync('cc', ['-Wall', '-Wextra', '-Werror', '-O2', '-Wl,--export-dynamic', path.join(root, 'test/shell.d/fixtures/plymouth-render.c'), '-o', executable, ...flags, '-ldl'], { stdio: 'inherit' })
  pass('native renderer compiles with warnings treated as errors')

  const descriptor = fs.readFileSync(path.join(assets, 'omarchy.plymouth'), 'utf8')
  assert(descriptor.includes('[script-env-vars]\nShutdownAnimation=dust-drift\nShutdownDuration=2.4'), 'packaged theme selects Dust drift at 2.4 seconds')
  const reference = run({ style: 'none' })
  assert(staysStatic(reference), 'none preserves the static shutdown logo')

  const dust = run()
  assertEqual(dust[0].hash, reference[0].hash, 'initial hold exactly matches the original logo')
  assert(dust[30].foreground > 0 && dust[30].hash !== dust[0].hash, 'native frames visibly change during breakup')
  assert(endsBlank(dust), 'animation completes and never loops')

  for (const style of [null, 'unknown']) assert(staysStatic(run({ style })), 'missing/unknown style falls back to static')
  for (const mode of ['boot', 'reboot', 'updates']) {
    const rows = run({ mode })
    assert(staysStatic(rows), `${mode}: animation does not run`)
    assertEqual(rows[0].hash, reference[0].hash, `${mode}: unchanged centered logo`)
  }

  const fast = run({ duration: '.8' })
  const slow = run({ duration: '5', frames: 170 })
  assert(blankFrame(fast) <= 24 && blankFrame(dust) > 24, 'short duration accelerates completion')
  assert(blankFrame(slow) > 72 && endsBlank(slow), 'long duration extends motion and still completes')
  for (const duration of [null, '', 'oops', '0', '0.7', '5.1', '-2', '1..2', '999999']) {
    const rows = run({ duration })
    assert(blankFrame(rows) > 24 && blankFrame(rows) <= 72 && endsBlank(rows), `invalid/missing duration ${JSON.stringify(duration)} safely uses 2.4 seconds`)
  }

  const bootPrompt = run({ mode: 'boot', scenario: 'password' })
  assert(bootPrompt[1].foreground > reference[0].foreground, 'boot password UI is visible')
  assert(bootPrompt[50].foreground > reference[0].foreground, 'boot progress UI appears after the password clears')
  assertDeepEqual(bootPrompt, run({ mode: 'boot', scenario: 'password', style: 'none' }), 'boot password/progress frames are independent of animation setting')
  const progress = run({ mode: 'boot', scenario: 'progress' })
  assert(progress[90].hash !== progress[60].hash, 'real boot progress advances after disk unlock')
  assertEqual(progress[60].hash, progress[59].hash, 'a lower boot progress update never moves the bar backward')

  const interrupted = run({ scenario: 'interrupt' })
  assert(interrupted[26].foreground > reference[0].foreground, 'a shutdown password prompt restores the logo and displays controls')
  assertEqual(interrupted[50].hash, reference[0].hash, 'clearing a shutdown prompt restores the static screen')
  assertEqual(interrupted[100].hash, reference[0].hash, 'cancelled particles never restart after input')
  const late = run({ scenario: 'late-password' })
  assert(late[80].foreground === 0 && late[86].foreground > reference[0].foreground, 'a prompt after animation completion also restores the logo')
  const messages = run({ scenario: 'message', frames: 150 })
  assert(messages[105].foreground > 0 && messages[145].foreground === 0, 'shutdown messages remain visible and can be hidden after animation')

  // Custom logos retain their own color/alpha, including partial edge tiles.
  try {
    execFileSync('magick', ['-version'], { stdio: 'ignore' })
    const custom = path.join(scratch, 'custom')
    fs.mkdirSync(custom)
    for (const file of fs.readdirSync(assets).filter(file => file.endsWith('.png') && file !== 'logo.png')) fs.symlinkSync(path.join(assets, file), path.join(custom, file))
    for (const size of ['137x33!', '1x513!']) {
      execFileSync('magick', [path.join(assets, 'logo.png'), '-resize', size, '-fill', '#e85e99', '-colorize', '100', path.join(custom, 'logo.png')])
      const rows = run({ imageDir: custom, width: 1024, height: 768 })
      assertEqual(rows[0].hash, run({ imageDir: custom, style: 'none', width: 1024, height: 768 })[0].hash, `${size}: custom logo starts intact`)
      assert(endsBlank(rows), `${size}: custom logo finishes without edge-tile errors`)
    }
  } catch (error) {
    if (error.code === 'ENOENT') pass('SKIP custom-logo generation: ImageMagick not installed')
    else throw error
  }
} finally {
  // Only this test's unique scratch directory is removed.
  fs.rmSync(scratch, { recursive: true, force: true })
}
JS
