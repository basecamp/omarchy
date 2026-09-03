#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

agent_qml="$ROOT/shell/plugins/agents/Agent.qml"
[[ -f $agent_qml ]] || fail "Agent.qml is present"

# Must have a fallback Timer for when inotify watch-rearm fails (#9974).
grep -F 'Timer' "$agent_qml" >/dev/null || fail "Agent.qml has a fallback Timer"
grep -F 'interval: 120000' "$agent_qml" >/dev/null ||
  fail "fallback Timer runs every 2 minutes"
grep -F 'repeat: true' "$agent_qml" >/dev/null ||
  fail "fallback Timer repeats"
grep -F 'onTriggered: agentFile.reload()' "$agent_qml" >/dev/null ||
  fail "fallback Timer calls FileView.reload()"

# FileView still has the primary inotify path.
grep -F 'watchChanges: true' "$agent_qml" >/dev/null ||
  fail "Agent.qml still uses inotify for low-latency updates"
grep -F 'onFileChanged: reload()' "$agent_qml" >/dev/null ||
  fail "Agent.qml still reloads on inotify events"
pass "Agent.qml has a 2-minute fallback reload Timer"

# Verify Timer is after FileView (accessing its id).
python3 - <<'PY' || fail "fallback Timer is placed after FileView"
from pathlib import Path
import os, re

qml = Path(os.environ["ROOT"], "shell/plugins/agents/Agent.qml").read_text()
fv_pos = qml.index("FileView {")
timer_pos = qml.index("Timer {")
assert timer_pos > fv_pos, "Timer must appear after FileView (agentFile id)"
assert "agentFile.reload()" in qml, "Timer calls agentFile.reload()"
PY
pass "fallback Timer references the FileView id"