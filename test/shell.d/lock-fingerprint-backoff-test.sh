#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

const capture = (pattern, description) => {
  const match = pattern.exec(serviceQml)
  assert(match !== null, description)
  return match[1]
}

const baseMs = Number(capture(/readonly property int fingerprintRetryBaseMs: (\d+)/, 'the base retry interval is declared'))
const maxMs = Number(capture(/readonly property int fingerprintRetryMaxMs: (\d+)/, 'the retry ceiling is declared'))
const body = capture(/function fingerprintRetryDelay\(streak\) \{([\s\S]*?)\n  \}/, 'the retry delay is computed by fingerprintRetryDelay()')

const fingerprintRetryDelay = new Function('streak', 'fingerprintRetryBaseMs', 'fingerprintRetryMaxMs', body)
const delay = (streak) => fingerprintRetryDelay(streak, baseMs, maxMs)

assert(delay(0) === baseMs, 'no error streak retries at the base interval')
assert(delay(1) === baseMs, 'first device error retries at the base interval')
assert(delay(2) === baseMs * 2, 'second consecutive device error doubles the delay')
assert(delay(3) === baseMs * 4, 'third consecutive device error doubles again')
assert(delay(8) === maxMs, 'the delay saturates at the ceiling')
assert(delay(80) === maxMs, 'a long error streak never exceeds the ceiling')

// A reader stuck erroring must not be retried more than a handful of times per
// minute; the unbounded 250ms retry it replaces managed ~240.
let elapsed = 0
let attempts = 0
for (let streak = 1; elapsed < 60000; streak++) {
  elapsed += delay(streak)
  attempts++
}
assert(attempts <= 10, 'a persistently failing reader is retried at most 10 times a minute, got ' + attempts)

assert(
  /onError: function\(error\) \{\s*root\.fingerprintAuthenticating = false\s*root\.scheduleFingerprintRetry\(true\)/.test(serviceQml),
  'a device-level PAM error schedules a backed-off retry'
)

assert(
  /\} else if \(fingerprintConfigured\) \{\s*scheduleFingerprintRetry\(false\)/.test(serviceQml),
  'a failed swipe schedules a retry without counting as a device error'
)

assert(
  /if \(result === PamResult\.Success\) \{\s*fingerprintErrorStreak = 0/.test(serviceQml),
  'a successful verify clears the error streak'
)

assert(
  /fingerprintErrorStreak = 0\s*fingerprintRetryTimer\.stop\(\)/.test(serviceQml),
  'resetting authentication state clears the error streak'
)

assert(
  !/interval: 250/.test(serviceQml),
  'the retry timer takes its interval from the backoff, not a hardcoded literal'
)
JS
