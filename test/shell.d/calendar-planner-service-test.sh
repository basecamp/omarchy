#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

require_compositor "calendar planner service test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping calendar planner service test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
test_home="$TMPDIR/home"
config_dir="$TMPDIR/calendar-planner-service"
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
mkdir -p "$test_home" "$config_dir"
cp "$SHELL_TEST_DIR/fixtures/calendar-planner-service/shell.qml" "$config_dir/shell.qml"
ln -s "$ROOT/shell/Commons" "$config_dir/Commons"

service_url="file://$ROOT/shell/plugins/panels/clock/Service.qml"
OMARCHY_PATH="$ROOT" \
OMARCHY_QML_TEST_RESULT="$result" \
OMARCHY_QML_SERVICE_URL="$service_url" \
HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_CACHE_HOME="$test_home/.cache" \
XDG_STATE_HOME="$test_home/.local/state" \
QML2_IMPORT_PATH="$ROOT/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
QML_IMPORT_PATH="$ROOT/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
PATH="$ROOT/bin:$PATH" \
  quickshell -p "$config_dir" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..160}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,240p' "$log" >&2
    fail "calendar planner service quickshell exited before writing result"
  fi
  sleep 0.1
done

[[ -s $result ]] || {
  sed -n '1,240p' "$log" >&2
  fail "calendar planner service test timed out"
}

jq -e '.ok == true' "$result" >/dev/null || {
  jq . "$result" >&2
  sed -n '1,240p' "$log" >&2
  fail "calendar planner service lifecycle checks pass"
}

pass "calendar planner service lifecycle checks pass"
