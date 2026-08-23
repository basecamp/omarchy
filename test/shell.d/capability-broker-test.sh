#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

broker="$ROOT/shell/services/CapabilityBroker.qml"
ws="$ROOT/shell/services/WindowService.qml"
shell="$ROOT/shell/shell.qml"

[[ -f $broker ]] || fail "CapabilityBroker.qml exists"
grep -Fq 'function catalog' "$broker" || fail "broker exposes a window verb catalog"
grep -Fq 'function permit' "$broker" || fail "broker checks actor permission"
grep -Fq 'function record' "$broker" || fail "broker appends an operation ledger"
grep -Fq 'capability-ledger.json' "$broker" || fail "ledger is durable under ~/.local/state/omarchy/ultimate/"
grep -Fq 'function invoke' "$broker" || fail "broker dispatches to WindowService"
grep -Fq 'function undoLast' "$broker" || fail "broker inverts the last recorded window operation"
grep -Fq 'actor === "ipc"' "$broker" || fail "IPC calls are a tagged actor"
grep -Fq 'actor === "ui"' "$broker" || fail "human UI calls are a tagged actor"
grep -Fq 'actor === "agent"' "$broker" || fail "agent calls are a tagged actor"
pass "broker catalogs, permits, records, and dispatches window verbs"

grep -Fq 'function _ok' "$ws" || fail "WindowService success is { changed, error }"
grep -Fq 'function _err' "$ws" || fail "WindowService errors are { title, explanation, detail }"
grep -Fq 'function _finish' "$ws" || fail "WindowService writers record through the broker"
grep -Fq 'capabilityBroker.record("window"' "$ws" || fail "QML writers and IPC share the same ledger path"
grep -Fq '{ verb: "restoreNormal", address: target }' "$ws" || fail "snap/maximize record restoreNormal as the invert"
grep -Fq '{ verb: "restoreLayout" }' "$ws" || fail "saveLayout records restoreLayout as the invert"
pass "WindowService writers share { changed, error } and ledger undo tokens"

grep -Fq 'function windowIpc' "$shell" || fail "window IPC serializes the service result object"
grep -Fq 'capabilityBroker.invoke' "$shell" || fail "window invoke IPC is the broker, not a second agent API"
grep -Fq 'capabilityBroker.undoLast' "$shell" || fail "window undoLast IPC is the broker"
grep -Fq 'windowService._actor = "ipc"' "$shell" || fail "window IPC tags the actor before the same WindowService verbs"
grep -Fq 'windowService.close(windows[i].address)' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "Superbar close uses WindowService.close, the same verb as IPC"
if grep -Eq 'IpcHandler \{[[:space:]]*$' "$shell"; then
  :
fi
if awk '
  $0 ~ /target: "window"/ { win = 1 }
  win && /return "ok"/ && $0 !~ /function ping/ { found = 1 }
  win && /target:/ && $0 !~ /target: "window"/ { win = 0 }
  END { exit found ? 0 : 1 }
' "$shell"; then
  fail "window IPC must not return a bare ok string except ping"
fi
grep -Fq 'function ping(): string { return "ok" }' "$shell" || fail "window ping stays a liveness string"
pass "IPC and QML call the same WindowService verbs and serialize { changed, error }"
