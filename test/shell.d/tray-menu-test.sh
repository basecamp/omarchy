#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""
MOCK_PID=""

cleanup() {
  if [[ -n $MOCK_PID ]] && kill -0 "$MOCK_PID" 2>/dev/null; then
    kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
  fi
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
  return 0
}
trap cleanup EXIT

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping tray menu activation test"
  exit 0
fi

require_command jq
require_command python

python - <<'PY' || {
import dbus
import gi
PY
  pass "python DBus bindings unavailable; skipping tray menu activation test"
  exit 0
}

TMPDIR=$(mktemp -d)
config_dir="$TMPDIR/tray-menu-activation"
result="$TMPDIR/result.json"
event_result="$TMPDIR/event"
ready="$TMPDIR/ready"
qs_log="$TMPDIR/quickshell.log"
mock_log="$TMPDIR/mock-sni.log"
mkdir -p "$config_dir" "$TMPDIR/home"
cp "$SHELL_TEST_DIR/fixtures/tray-menu-activation/shell.qml" "$config_dir/shell.qml"

OMARCHY_PATH="$ROOT" \
OMARCHY_QML_TEST_RESULT="$result" \
HOME="$TMPDIR/home" \
  quickshell -p "$config_dir" --no-color >"$qs_log" 2>&1 &
QS_PID=$!

OMARCHY_TRAY_MENU_EVENT_RESULT="$event_result" \
OMARCHY_TRAY_MENU_READY="$ready" \
  python "$SHELL_TEST_DIR/fixtures/tray-menu-activation/mock-sni.py" >"$mock_log" 2>&1 &
MOCK_PID=$!

for _ in {1..80}; do
  [[ -s $event_result ]] && break

  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,160p' "$qs_log" >&2
    fail "tray menu activation quickshell exited before triggering menu item"
  fi

  if ! kill -0 "$MOCK_PID" 2>/dev/null; then
    sed -n '1,160p' "$mock_log" >&2
    fail "mock StatusNotifierItem exited before receiving menu event"
  fi

  sleep 0.1
done

if [[ ! -s $event_result ]]; then
  [[ -s $result ]] && jq . "$result" >&2
  printf 'Quickshell log:\n' >&2
  sed -n '1,160p' "$qs_log" >&2
  printf 'Mock SNI log:\n' >&2
  sed -n '1,160p' "$mock_log" >&2
  fail "tray menu sends DBusMenu clicked event"
fi

pass "tray menu sends DBusMenu clicked event"
