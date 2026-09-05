#!/bin/bash

set -euo pipefail

# ScreenRecording.qml must not freeze on the last known state when a pgrep
# Process never leaves running, and must notice an abnormally killed recorder
# without waiting for omarchy.indicators refresh.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

indicator="$ROOT/shell/plugins/bar/indicators/ScreenRecording.qml"
[[ -f $indicator ]] || fail "ScreenRecording indicator is present"

grep -q 'probeWatchdog' "$indicator" ||
  fail "indicator watches for a stuck status Process"
grep -q 'statusProc.running = false' "$indicator" ||
  fail "stuck-probe path clears Process.running so refresh can run again"
grep -q 'pollTimer' "$indicator" ||
  fail "indicator polls recording state on a timer"
grep -Eq 'interval:[[:space:]]*2000' "$indicator" ||
  fail "probe/poll intervals stay short enough to recover without a shell restart"

# refresh must not permanently no-op solely because running is true without a
# way to clear it.
if ! grep -A20 'function refresh' "$indicator" | grep -q 'probeWatchdog'; then
  fail "refresh arms the stuck-probe watchdog when a probe is already running"
fi

grep -q 'onExited' "$indicator" || fail "indicator still updates recording from pgrep exit code"
grep -q 'omarchy-capture-screenrecording --stop-recording' "$indicator" ||
  fail "active click still stops the recorder"

pass "ScreenRecording indicator recovers from stuck probes and polls after crashes"
