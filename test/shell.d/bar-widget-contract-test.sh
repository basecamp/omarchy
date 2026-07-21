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
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  pass "no Wayland compositor; skipping bar widget contract test"
  exit 0
fi

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping bar widget contract test"
  exit 0
fi

require_command jq
require_command python3

bar_widgets=$(ROOT="$ROOT" python3 <<'PY'
import base64
import json
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
entries = []
for manifest_path in sorted((root / "shell/plugins").glob("**/manifest.json")) + sorted((root / "shell/plugins").glob("**/*.manifest.json")):
  manifest = json.loads(manifest_path.read_text())
  if "bar-widget" not in manifest.get("kinds", []):
    continue
  entry_point = manifest.get("entryPoints", {}).get("barWidget")
  if not entry_point:
    continue
  entries.append({
    "id": manifest["id"],
    "url": (manifest_path.parent / entry_point).resolve().as_uri(),
    "manifest": manifest,
  })

print(base64.b64encode(json.dumps(entries).encode()).decode())
PY
)

TMPDIR=$(mktemp -d)
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
config_dir="$TMPDIR/bar-widget-contract"
mkdir -p "$config_dir" "$TMPDIR/home"
cp "$SHELL_TEST_DIR/fixtures/bar-widget-contract/shell.qml" "$config_dir/shell.qml"
ln -s "$ROOT/shell/Ui" "$config_dir/Ui"
ln -s "$ROOT/shell/Commons" "$config_dir/Commons"

OMARCHY_PATH="$ROOT" \
OMARCHY_QML_TEST_RESULT="$result" \
OMARCHY_QML_BAR_WIDGETS="$bar_widgets" \
HOME="$TMPDIR/home" \
QML2_IMPORT_PATH="$ROOT/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
QML_IMPORT_PATH="$ROOT/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
PATH="$ROOT/bin:$PATH" \
  quickshell -p "$config_dir" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,220p' "$log" >&2
    fail "bar widget contract quickshell exited before writing result"
  fi
  sleep 0.1
done

[[ -s $result ]] || {
  sed -n '1,220p' "$log" >&2
  fail "bar widget contract test timed out"
}

if ! jq -e '.ok == true' "$result" >/dev/null; then
  printf 'Bar widget contract result:\n' >&2
  jq . "$result" >&2
  printf 'Bar widget contract log:\n' >&2
  sed -n '1,220p' "$log" >&2
  fail "bar widget contracts pass"
fi

pass "bar widget contracts pass"
