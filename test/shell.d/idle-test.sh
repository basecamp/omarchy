#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const idle = requireFromRoot('shell/plugins/services/idle/IdleModel.js')

assertEqual(idle.secondsFromConfig('42.9', 10), 42, 'idle floors configured seconds')
assertEqual(idle.secondsFromConfig('-1', 10), 10, 'idle rejects negative seconds')
assertEqual(idle.secondsFromConfig('nope', 10), 10, 'idle rejects invalid seconds')

assertDeepEqual(idle.eventParts({ data: 'a,b,c' }, 2), ['a', 'b', 'c'], 'idle parses raw event data')
assertDeepEqual(
  idle.eventParts({ parse: function(count) { return ['parsed', count] } }, 4),
  ['parsed', 4],
  'idle prefers event parser when available'
)

assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true }, 'b', true),
  { windows: { a: true, b: true }, count: 2 },
  'idle adds visible screensaver windows'
)
assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true, b: true }, 'a', false),
  { windows: { b: true }, count: 1 },
  'idle removes closed screensaver windows'
)
assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true }, '', false),
  { windows: { a: true }, count: 1 },
  'idle leaves screensaver windows unchanged without an address'
)
JS
