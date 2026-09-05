#!/bin/bash

# The daemon contract ends at the idle service: the QML must read the
# daemon's state through the tolerant model parser, gate the IdleMonitor on
# it, and cancel an in-flight cycle when an inhibit arrives. These are
# wiring assertions in the powerprofiles-set-test style; the parser itself
# is covered by the node tests in idle-test.sh.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

service="$ROOT/shell/plugins/services/idle/Service.qml"
[[ -f $service ]] || fail "idle Service.qml exists"

rg -F 'externalInhibitFromState' "$service" >/dev/null ||
  fail "idle service parses D-Bus inhibit state through IdleModel"
pass "idle service parses D-Bus inhibit state through IdleModel"

rg -F 'IdleModel.idleEnabledAfter' "$service" >/dev/null ||
  fail "idle service gates IdleMonitor through the tested model gate"
pass "idle service gates IdleMonitor through the tested model gate"

rg -F 'idle-inhibit' "$service" >/dev/null ||
  fail "idle service watches the inhibit daemon's state directory"
pass "idle service watches the inhibit daemon's state directory"

# Liveness rides in the state itself: snapshots carry the serving pid, and
# the probe script is what refuses a dead daemon's last write. Assert both
# halves so neither can regress silently.
[[ -x $ROOT/bin/omarchy-idle-inhibit-probe ]] ||
  fail "the inhibit probe script exists"
pass "the inhibit probe script exists"

rg -F 'omarchy-idle-inhibit-probe' "$service" >/dev/null ||
  fail "idle service consumes state through the liveness-aware probe"
pass "idle service consumes state through the liveness-aware probe"

# SplitParser.onRead never fires when the probe emits no bytes (dead pid).
# The Process must apply an empty state on exit so a crash cannot pin idle off.
python3 - "$service" <<'PY' || fail "probe exit without stdout applies an empty inhibit state"
import re
import sys

qml = open(sys.argv[1]).read()
block = re.search(r"id:\s*externalInhibitProbe\b.*?(?=\n  (?:Process|FileView|Timer|Component|IpcHandler)\b|\Z)", qml, re.S)
if not block:
    sys.exit(1)
text = block.group(0)
if "onExited" not in text or 'applyExternalInhibitState("")' not in text:
    sys.exit(1)
if "sawProbeOutput" not in text:
    sys.exit(1)
PY
pass "probe exit without stdout applies an empty inhibit state"

grep -q '"pid"' "$ROOT/bin/omarchy-idle-inhibit-daemon" ||
  fail "daemon snapshots carry the serving pid"
pass "daemon snapshots carry the serving pid"

rg -F 'external-inhibit' "$service" >/dev/null ||
  fail "an arriving inhibit cancels an in-flight idle cycle"
pass "an arriving inhibit cancels an in-flight idle cycle"

# The watcher must watch the directory, not the file: the daemon publishes
# with an atomic rename, which surfaces as a change in the containing
# directory, and the stay-awake watcher in the same file established the
# pattern for exactly this reason.
python3 - "$service" <<'PY' || fail "the inhibit watcher watches a directory, not the file"
import re
import sys

qml = open(sys.argv[1]).read()

watchers = re.findall(r"FileView\s*\{[^}]*path:\s*root\.(\w+)", qml, re.S)
inhibit_watchers = [
    name for name in watchers if "nhibit" in name
]
if not inhibit_watchers:
    sys.exit(1)
PY
pass "the inhibit watcher watches a directory, not the file"

# A daemon that is not running, or a runtime dir that does not exist yet,
# must read as "no external inhibits" rather than wedging the timers on.
rg -F 'externalInhibit: false' "$service" >/dev/null ||
  fail "absent inhibit state degrades to no external inhibit"
pass "absent inhibit state degrades to no external inhibit"

rg -F 'externalInhibit: root.externalInhibit' "$service" >/dev/null ||
  fail "idle status reports the external inhibit state"
pass "idle status reports the external inhibit state"
