#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
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

assert(notifications.shouldBypassDnd({ appName: 'omarchy-action', urgency: 1 }, 2), 'omarchy action toasts bypass DND')
assert(notifications.shouldBypassDnd({ appName: 'notify-send', urgency: 2 }, 2), 'critical notify-send bypasses DND')
assert(!notifications.shouldBypassDnd({ appName: 'notify-send', urgency: 1 }, 2), 'normal notify-send does not bypass DND')
assert(!notifications.shouldBypassDnd({ appName: 'Slack', urgency: 2 }, 2), 'critical app notifications do not bypass DND')
assert(!notifications.shouldBypassDnd({ appName: 'omarchy-menu-keybindings', urgency: 1 }, 2), 'omarchy command app names do not bypass DND')
assert(!notifications.isEphemeralApp('omarchy-menu-keybindings'), 'notifications treat omarchy command app names as normal apps')

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

assertEqual(notifications.imageExtension('/tmp/screenshot.PNG'), 'png', 'notifications normalize image extensions')
assertEqual(notifications.imageExtension('/tmp/no-extension'), 'png', 'notifications default missing image extension')
assertEqual(notifications.imageExtension('/tmp/archive.reallylong'), 'png', 'notifications reject suspicious image extensions')
JS
