#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const os = require('os')
const { spawnSync } = require('child_process')
const notifications = requireFromRoot('shell/plugins/notifications/NotificationLogic.js')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/notifications/Service.qml'), 'utf8')

function functionBody(name) {
  const marker = `function ${name}(`
  const start = serviceQml.indexOf(marker)
  assert(start >= 0, `notifications service defines ${name}`)
  const open = serviceQml.indexOf('{', start)
  const nextFunction = serviceQml.indexOf('\n  function ', open + 1)
  const close = serviceQml.lastIndexOf('}', nextFunction)
  assert(close > open, `notifications service closes ${name}`)
  return serviceQml.slice(open + 1, close)
}

function assembledJob(name, entry, paths) {
  let queued = null
  const done = () => {}
  const body = functionBody(name)
  const build = new Function(
    name === 'persistPopupFile' ? 'snapshot' : 'entry',
    'done', 'NotificationLogic', 'NotificationUrgency', 'imagesDir',
    'popupStateDir', 'historyDir', 'historyLimit', 'copyImagesScript',
    'trimHistoryScript', 'enqueuePopupFileJob', body
  )
  build(
    entry, done, notifications, { Normal: 1 }, paths.images,
    paths.popup, paths.history, 10,
    'while (( $# >= 2 )); do cp -- "$1" "$2"; shift 2; done\n',
    ':', (...args) => { queued = args }
  )
  assert(queued, `notifications service queues ${name}`)
  return { command: queued[0], stdin: queued[1], done: queued[2], expectedDone: done }
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchy-notification-stdin-'))
try {
  const paths = {
    popup: path.join(tmp, 'popups'),
    history: path.join(tmp, 'history'),
    images: path.join(tmp, 'images')
  }
  const sourceImage = path.join(tmp, 'sender image')
  fs.writeFileSync(sourceImage, 'image bytes')
  const entry = {
    id: 17,
    originalId: 17,
    app: 'Mail',
    appIcon: sourceImage,
    summary: 'private "subject" $(not a command)\nsecond line',
    body: "apostrophe ' and backtick ` stay private",
    image: '',
    glyph: '',
    urgency: 1,
    expireTimeout: 4000,
    timestamp: 123456
  }
  const expected = notifications.serializePopup(
    notifications.persistablePopup(entry, paths.images).entry,
    1
  )

  const popupJob = assembledJob('persistPopupFile', entry, paths)
  assertEqual(popupJob.stdin, expected, 'popup persistence carries notification JSON separately from argv')
  assert(!popupJob.command.some(arg => arg.includes(expected)), 'popup persistence does not expose notification JSON in argv')
  assert(popupJob.command.includes(sourceImage), 'popup persistence keeps image copy paths in argv')
  const popupRun = spawnSync(popupJob.command[0], popupJob.command.slice(1), {
    input: popupJob.stdin + '\n',
    encoding: 'utf8'
  })
  assertEqual(popupRun.status, 0, 'popup persistence command accepts notification JSON on stdin')
  assertEqual(
    fs.readFileSync(path.join(paths.popup, notifications.popupFileName(entry)), 'utf8'),
    expected + '\n',
    'popup persistence preserves special characters and newlines from stdin'
  )

  const historyJob = assembledJob('writeHistoryFile', entry, paths)
  assertEqual(historyJob.stdin, expected, 'history persistence carries notification JSON separately from argv')
  assert(!historyJob.command.some(arg => arg.includes(expected)), 'history persistence does not expose notification JSON in argv')
  assertEqual(historyJob.done, historyJob.expectedDone, 'history persistence keeps its queued completion callback')
  const historyRun = spawnSync(historyJob.command[0], historyJob.command.slice(1), {
    input: historyJob.stdin + '\n',
    encoding: 'utf8'
  })
  assertEqual(historyRun.status, 0, 'history persistence command accepts notification JSON on stdin')
  assertEqual(
    fs.readFileSync(path.join(paths.history, notifications.popupFileName(entry)), 'utf8'),
    expected + '\n',
    'history persistence preserves special characters and newlines from stdin'
  )
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}

assert(
  /popupFileQueue = popupFileQueue\.concat\(\[\{\s*command: command,[\s\S]{0,150}?stdin: stdin[\s\S]{0,150}?done: done/.test(serviceQml),
  'notifications service keeps each stdin payload with its serialized queue job'
)
assert(
  /popupFileProc\.command = job\.command[\s\S]{0,200}?runningPopupFileJobStdin = job\.stdin[\s\S]{0,200}?popupFileProc\.running = true/.test(serviceQml),
  'notifications service installs a queued stdin payload before starting its process'
)
assert(
  /id: popupFileProc[\s\S]{0,300}?stdinEnabled: true[\s\S]{0,300}?onStarted:[\s\S]{0,300}?write\(service\.runningPopupFileJobStdin \+ "\\n"\)[\s\S]{0,200}?runningPopupFileJobStdin = null/.test(serviceQml),
  'notifications service writes queued JSON only after start and clears it promptly'
)
JS
