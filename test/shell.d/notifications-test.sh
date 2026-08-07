#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const notifications = requireFromRoot('shell/plugins/notifications/NotificationLogic.js')

assert(notifications.isChromiumDerived('Brave Browser', ''), 'notifications detect chromium-derived apps by name')
assert(notifications.isChromiumDerived('', 'microsoft-edge'), 'notifications detect chromium-derived apps by icon')
assert(!notifications.isChromiumDerived('Slack', ''), 'notifications do not treat unrelated apps as chromium-derived')

assertEqual(
  notifications.sanitizeBody('<img src="x">Hello', 'Slack', ''),
  'Hello',
  'notifications strip inline image tags'
)

assertEqual(
  notifications.sanitizeBody('<a href="https://example.com">example.com</a> Message body', 'Chromium', ''),
  'Message body',
  'notifications strip chromium leading origin links'
)

assertEqual(
  notifications.sanitizeBody('https://example.com/path Message body', 'Chromium', ''),
  'Message body',
  'notifications strip chromium leading origin text'
)

assertEqual(
  notifications.sanitizeBody('https://example.com/path Message body', 'Slack', ''),
  'https://example.com/path Message body',
  'notifications keep non-browser leading origin text'
)

assert(notifications.summaryStartsWithGlyph('󰂚  Silenced'), 'notifications detect glyph-prefixed summaries')
assert(!notifications.summaryStartsWithGlyph('Normal summary'), 'notifications ignore normal summaries as glyph-prefixed')
assert(notifications.shouldRenderCompactGlyph('K', '', true), 'notifications render glyph-only single-line toasts compactly')
assert(!notifications.shouldRenderCompactGlyph('K', '', false), 'notifications give glyph hints with bodies the large icon slot')
assert(!notifications.shouldRenderCompactGlyph('K', 'file:///tmp/image.png', true), 'notifications keep image-backed glyph hints in the icon slot')

assert(notifications.shouldBypassDnd({ appName: 'omarchy-action', urgency: 1 }, 2), 'omarchy action toasts bypass DND')
assert(notifications.shouldBypassDnd({ appName: 'notify-send', urgency: 2 }, 2), 'critical notify-send bypasses DND')
assert(!notifications.shouldBypassDnd({ appName: 'notify-send', urgency: 1 }, 2), 'normal notify-send does not bypass DND')
assert(!notifications.shouldBypassDnd({ appName: 'Slack', urgency: 2 }, 2), 'critical app notifications do not bypass DND')
assert(!notifications.shouldBypassDnd({ appName: 'omarchy-menu-keybindings', urgency: 1 }, 2), 'omarchy command app names do not bypass DND')
assert(!notifications.isEphemeralApp('omarchy-menu-keybindings'), 'notifications treat omarchy command app names as normal apps')

assertDeepEqual(
  notifications.popupPlacement('top', 32, 6),
  {
    anchors: { top: true, bottom: false, left: false, right: true },
    margins: { top: 32, bottom: 6, left: 6, right: 6 }
  },
  'notifications clear a top bar while staying anchored top-right'
)
assertDeepEqual(
  notifications.popupPlacement('right', 32, 6),
  {
    anchors: { top: true, bottom: false, left: false, right: true },
    margins: { top: 6, bottom: 6, left: 6, right: 32 }
  },
  'notifications clear a right bar while staying anchored top-right'
)
assertDeepEqual(
  notifications.popupPlacement('bottom', 32, 6),
  {
    anchors: { top: true, bottom: false, left: false, right: true },
    margins: { top: 6, bottom: 6, left: 6, right: 6 }
  },
  'notifications ignore a bottom bar for popup placement'
)
assertDeepEqual(
  notifications.popupPlacement('left', 32, 6),
  {
    anchors: { top: true, bottom: false, left: false, right: true },
    margins: { top: 6, bottom: 6, left: 6, right: 6 }
  },
  'notifications ignore a left bar for popup placement'
)

const notification = {
  id: 12,
  appName: 'Mail',
  appIcon: 'mail',
  summary: 42,
  body: 'Body',
  image: 'file:///tmp/mail.png',
  hints: { 'omarchy-glyph': '!' },
  urgency: 1,
  expireTimeout: 1.5
}
const snapshot = notifications.snapshotOf(notification, 12345)
assertDeepEqual(
  {
    id: snapshot.id,
    originalId: snapshot.originalId,
    app: snapshot.app,
    appIcon: snapshot.appIcon,
    summary: snapshot.summary,
    body: snapshot.body,
    image: snapshot.image,
    glyph: snapshot.glyph,
    urgency: snapshot.urgency,
    expireTimeout: snapshot.expireTimeout,
    timestamp: snapshot.timestamp
  },
  {
    id: 12,
    originalId: 12,
    app: 'Mail',
    appIcon: 'mail',
    summary: '42',
    body: 'Body',
    image: 'file:///tmp/mail.png',
    glyph: '!',
    urgency: 1,
    expireTimeout: 1.5,
    timestamp: 12345
  },
  'notifications create stable snapshots'
)

const history = notifications.parseHistory(JSON.stringify({
  dnd: true,
  pending: [
    { id: 1, originalId: 10, summary: 'old', timestamp: 100 },
    { id: 2, originalId: 10, summary: 'new', timestamp: 200 },
    { id: 3, originalId: 11, summary: 'other', timestamp: 150 }
  ],
  past: [
    { id: 4, summary: 'past', timestamp: 50 }
  ],
  entries: [
    { id: 5, summary: 'legacy', timestamp: 75 }
  ]
}), 1, 100)

assertEqual(history.dnd, true, 'notifications parse persisted DND state')
assertEqual(history.hadDuplicates, true, 'notifications report duplicate history rows')
assertDeepEqual(
  history.pending.map(row => ({ id: row.id, originalId: row.originalId, summary: row.summary, urgency: row.urgency, timestamp: row.timestamp })),
  [
    { id: 2, originalId: 10, summary: 'new', urgency: 1, timestamp: 200 },
    { id: 3, originalId: 11, summary: 'other', urgency: 1, timestamp: 150 }
  ],
  'notifications dedupe pending history by original id'
)
assertDeepEqual(
  history.past.map(row => row.summary),
  ['legacy', 'past'],
  'notifications merge legacy entries into past history'
)
assertDeepEqual(
  notifications.parseHistory(JSON.stringify({ pending: [{ id: 1, timestamp: 1 }] }), 1, 0).pending,
  [],
  'notifications history parser supports zero result cap'
)
assert(notifications.parseHistory('{', 1, 100).error, 'notifications flag invalid history JSON')

const recentRows = notifications.recentHistoryRows(
  [
    { id: 1, originalId: 10, summary: 'pending-old', timestamp: 100 },
    { id: 2, originalId: 11, summary: 'pending-new', timestamp: 700 },
    { id: 3, originalId: 12, summary: 'pending-mid', timestamp: 300 }
  ],
  [
    { id: 4, originalId: 13, summary: 'past-newest', timestamp: 900 },
    { id: 5, originalId: 14, summary: 'past-second', timestamp: 800 },
    { id: 6, originalId: 10, summary: 'past-replaced', timestamp: 200 },
    { id: 7, originalId: 15, summary: 'past-extra', timestamp: 50 }
  ],
  5,
  1
)
assertDeepEqual(
  recentRows.map(row => row.summary),
  ['past-newest', 'past-second', 'pending-new', 'pending-mid', 'past-replaced'],
  'notifications pick the last five history rows across pending and past'
)
assertEqual(recentRows.length, 5, 'notifications history replay is capped at five rows')

const popup = {
  id: 7,
  originalId: 7,
  app: 'Mail',
  appIcon: 'mail',
  summary: 'New message',
  body: 'Body',
  image: '',
  glyph: '',
  urgency: 2,
  expireTimeout: 2500,
  timestamp: 1000
}
assertEqual(notifications.popupFileName(popup), '1000-7.json', 'notifications name popup files by timestamp and id')
assertEqual(
  notifications.serializePopup(popup, 1).indexOf('\n'),
  -1,
  'notifications serialize popups to a single line'
)
assertEqual(
  notifications.popupEntry({ id: 1, timestamp: 5 }, 1).urgency,
  1,
  'notifications default popup urgency to normal'
)
assertEqual(
  notifications.popupEntry({ id: 1, timestamp: 5, expireTimeout: 4000 }, 1).expireTimeout,
  4000,
  'notifications preserve popup expire timeouts unlike history rows'
)

const popupFiles = notifications.parsePopupFiles(
  [
    notifications.serializePopup({ id: 1, originalId: 1, summary: 'old-generation', urgency: 2, timestamp: 100 }, 1),
    notifications.serializePopup({ id: 1, originalId: 1, summary: 'new-generation', urgency: 1, timestamp: 300 }, 1),
    notifications.serializePopup({ id: 2, originalId: 2, summary: 'critical', urgency: 2, timestamp: 200 }, 1),
    '{ torn write'
  ].join('\n'),
  1
)
assertDeepEqual(
  popupFiles.map(row => row.summary),
  ['new-generation', 'critical', 'old-generation'],
  'notifications restore every persisted popup newest-first, never deduping ids across server generations'
)
assertDeepEqual(
  notifications.parsePopupFiles('', 1),
  [],
  'notifications restore nothing from an empty popup dir'
)

assert(!notifications.popupExpired({ timestamp: 0 }, 0, 999999), 'critical popups never expire on restore')
assert(!notifications.popupExpired({ timestamp: 1000 }, 8000, 5000), 'popups within their lifetime are restored')
assert(notifications.popupExpired({ timestamp: 1000 }, 8000, 9000), 'popups past their lifetime are not restored')
assert(
  !notifications.popupExpired({ timestamp: 1000, deadline: 20000 }, 8000, 15000),
  'a restore-reset deadline outranks the original popup timestamp'
)
assert(
  notifications.popupExpired({ timestamp: 1000, deadline: 20000 }, 8000, 20000),
  'popups past their reset deadline are not restored'
)
assertEqual(
  notifications.popupEntry(JSON.parse(notifications.serializePopup({ id: 1, originalId: 1, timestamp: 5, deadline: 9000 }, 1)), 1).deadline,
  9000,
  'notifications round-trip reset deadlines through popup files'
)
assertEqual(
  'deadline' in notifications.popupEntry({ id: 1, timestamp: 5 }, 1),
  false,
  'notifications omit the deadline field until a restore sets it'
)

assertEqual(notifications.imageExtension('/tmp/screenshot.PNG'), 'png', 'notifications normalize image extensions')
assertEqual(notifications.imageExtension('/tmp/no-extension'), 'png', 'notifications default missing image extension')
assertEqual(notifications.imageExtension('/tmp/archive.reallylong'), 'png', 'notifications reject suspicious image extensions')

const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/notifications/Service.qml'), 'utf8')
assert(
  /readonly property int historyReplayLimit: 5/.test(serviceQml),
  'notifications service limits history replay to five rows'
)
assert(
  /function showHistory\(\): string \{\s*return service\.showRecentHistory\(\)\s*\}/.test(serviceQml),
  'notifications history IPC replays recent notifications'
)
assert(
  /readonly property string popupStateDir: stateDir \+ "notifications\/"/.test(serviceQml),
  'notifications service persists popups under the omarchy state dir'
)
assert(
  serviceQml.split('persistPopupFile(snapshot)').length === 4,
  'notifications service persists both ephemeral and regular popups'
)
assert(
  /if \(entry\) \{\s*\n\s*deletePopupFileFor\(entry\)[\s\S]{0,200}?popupModel\.remove\(index\)/.test(serviceQml),
  'notifications service deletes the popup file when a popup leaves the screen'
)
assert(
  /restorePopupsProc\.running = true/.test(serviceQml),
  'notifications service restores persisted popups on startup'
)
assert(
  /if \(isRestoredRow\(row\)\) continue/.test(serviceQml),
  'notifications service protects restored popups from new-generation id collisions'
)
assert(
  /var ref = !restored && originalId >= 0 \? liveRefs\[originalId\] : null/.test(serviceQml),
  'notifications service never resolves a restored popup to a live server object'
)
assert(
  /markSeenByOriginalId\(originalId, timestamp\)/.test(serviceQml),
  'notifications service archives pending rows by id and timestamp'
)
assert(
  /popupFileName\(row\) !== keepFileName/.test(serviceQml),
  'notifications service keeps a same-millisecond replacement popup file'
)
assert(
  /awk 1 \\"\$1\\"\/\*\.json/.test(serviceQml),
  'notifications service delimits every popup file during restore'
)
JS
