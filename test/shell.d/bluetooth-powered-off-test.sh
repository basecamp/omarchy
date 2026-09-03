#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

qml="$ROOT/shell/plugins/panels/bluetooth/Panel.qml"
[[ -f $qml ]] || fail "bluetooth panel QML is present"

# poweredOffByUser flag (#9724)
grep -F 'property bool poweredOffByUser' "$qml" >/dev/null ||
  fail "bluetooth panel tracks powered-off state"
grep -F 'onAdapterChanged' "$qml" >/dev/null ||
  fail "bluetooth panel clears poweredOffByUser when adapter returns"

# Visibility must include powered-off case.
if grep -q 'visible: adapter !== null$' "$qml"; then
  fail "bluetooth panel must stay visible when powered off by user"
fi
grep -F 'visible: adapter !== null || poweredOffByUser' "$qml" >/dev/null ||
  fail "bluetooth panel stays visible when powered off by user"
pass "bluetooth panel stays visible when powered off by user"

# heroStatusText shows "Turned Off" not "No adapter" when powered off.
python3 - <<'PY' || fail "heroStatusText handles powered-off case"
from pathlib import Path
import os, re

qml = Path(os.environ["ROOT"], "shell/plugins/panels/bluetooth/Panel.qml").read_text()

# heroStatusText logic
m = re.search(r"readonly property string heroStatusText:\s*\{([^}]+)\}", qml)
assert m, "heroStatusText definition found"
body = m.group(1)
assert "poweredOffByUser" in body, "heroStatusText checks poweredOffByUser"
assert '"No adapter"' in body, "keeps No adapter for genuine absence"
assert '"Turned Off"' in body, "shows Turned Off when powered off"
PY
pass "bluetooth panel shows Turned Off when rfkill blocks the adapter"

# toggleBluetooth logic: set/clear flag, enable resume from poweredOffByUser.
python3 - <<'PY' || fail "toggleBluetooth handles all states"
from pathlib import Path
import os, re

qml = Path(os.environ["ROOT"], "shell/plugins/panels/bluetooth/Panel.qml").read_text()
m = re.search(r"function toggleBluetooth\(\)\s*\{([\s\S]*?)\n  \}", qml)
assert m, "toggleBluetooth definition found"
body = m.group(1)

assert "poweredOffByUser = true" in body, "toggle off sets the flag"
assert "adapter && adapter.enabled" in body, "toggle detects powered state"
assert "!adapter && poweredOffByUser" in body, "toggle resumes from rfkill block"
PY
pass "bluetooth toggle tracks poweredOffByUser and resumes from rfkill block"

# Existing toggle contract still good.
grep -F 'execDetached(["omarchy-bluetooth-power"' "$qml" >/dev/null ||
  fail "bluetooth toggle still dispatches to omarchy-bluetooth-power"
pass "bluetooth toggle still uses omarchy-bluetooth-power"