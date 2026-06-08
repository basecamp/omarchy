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

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  pass "no Wayland compositor; skipping manifest entrypoint load test"
  exit 0
fi

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping manifest entrypoint load test"
  exit 0
fi

require_command python3

manifest_entries=$(ROOT="$ROOT" python3 <<'PY'
import base64
import json
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
entries = []

kind_entry_points = {
  "bar": "bar",
  "bar-widget": "barWidget",
  "menu": "menu",
  "overlay": "overlay",
  "panel": "panel",
  "service": "service",
}

for manifest_path in sorted((root / "shell/plugins").glob("**/manifest.json")) + sorted((root / "shell/plugins").glob("**/*.manifest.json")):
  manifest = json.loads(manifest_path.read_text())
  for kind in manifest.get("kinds", []):
    entry_key = kind_entry_points.get(kind)
    entry_point = manifest.get("entryPoints", {}).get(entry_key)
    if not entry_point:
      continue
    entry_path = manifest_path.parent / entry_point
    entries.append({
      "id": manifest["id"],
      "kind": kind,
      "entryKey": entry_key,
      "entryPoint": entry_point,
      "url": entry_path.resolve().as_uri(),
      "manifest": manifest,
    })

print(base64.b64encode(json.dumps(entries).encode()).decode())
PY
)

TMPDIR=$(mktemp -d)
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
config_dir="$TMPDIR/manifest-entrypoints"
mkdir -p "$config_dir" "$TMPDIR/home"
cp "$SHELL_TEST_DIR/fixtures/manifest-entrypoints/shell.qml" "$config_dir/shell.qml"
ln -s "$ROOT/shell/Ui" "$config_dir/Ui"
ln -s "$ROOT/shell/Commons" "$config_dir/Commons"

OMARCHY_PATH="$ROOT" \
OMARCHY_QML_TEST_RESULT="$result" \
OMARCHY_QML_MANIFESTS="$manifest_entries" \
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
    fail "manifest entrypoint quickshell exited before writing result"
  fi
  sleep 0.1
done

[[ -s $result ]] || {
  sed -n '1,220p' "$log" >&2
  fail "manifest entrypoint load test timed out"
}

if ! jq -e '.ok == true' "$result" >/dev/null; then
  printf 'Manifest entrypoint result:\n' >&2
  jq . "$result" >&2
  printf 'Manifest entrypoint log:\n' >&2
  sed -n '1,220p' "$log" >&2
  fail "manifest entrypoints load"
fi

pass "manifest entrypoints load"
