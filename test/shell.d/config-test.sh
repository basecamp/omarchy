#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""

export PATH="$ROOT/bin:$PATH"

cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

require_command jq
require_command python3

jq empty "$ROOT/config/omarchy/shell.json"
pass "default shell.json is valid JSON"

jq -e '.version == 1 and (.bar.layout.left | type == "array") and (.bar.layout.center | type == "array") and (.bar.layout.right | type == "array")' "$ROOT/config/omarchy/shell.json" >/dev/null
pass "default shell.json has versioned bar layout"

jq -e '
  def ids: map(.id // .);
  .bar.layout.center | ids == [
    "omarchy.clock",
    "omarchy.weather",
    "omarchy.system-update",
    "omarchy.indicators"
  ]
' "$ROOT/config/omarchy/shell.json" >/dev/null
pass "default center layout keeps update next to weather"

jq -e '
  (.bar.centerAnchor // "") as $anchor |
  any(.bar.layout.center[]; (.id // .) == $anchor)
' "$ROOT/config/omarchy/shell.json" >/dev/null
pass "default center anchor exists in center layout"

ROOT="$ROOT" python3 <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["ROOT"])
config = json.loads((root / "config/omarchy/shell.json").read_text())
manifests = {}
for manifest_path in (root / "shell/plugins").glob("**/*.manifest.json"):
  data = json.loads(manifest_path.read_text())
  manifests[data.get("id", "")] = (manifest_path, data)
for manifest_path in (root / "shell/plugins").glob("**/manifest.json"):
  data = json.loads(manifest_path.read_text())
  manifests[data.get("id", "")] = (manifest_path, data)

entries = []
for section in ("left", "center", "right"):
  entries.extend(config["bar"]["layout"][section])

missing = []
bad = []
for entry in entries:
  widget_id = entry["id"] if isinstance(entry, dict) else str(entry)
  if not widget_id.startswith("omarchy."):
    continue

  row = manifests.get(widget_id)
  if row is None:
    missing.append(widget_id)
    continue
  manifest_path, manifest = row

  if "bar-widget" not in manifest.get("kinds", []):
    bad.append(f"{widget_id}: missing bar-widget kind")
  entry_point = manifest.get("entryPoints", {}).get("barWidget")
  if not entry_point:
    bad.append(f"{widget_id}: missing barWidget entry point")
  elif not (manifest_path.parent / entry_point).exists():
    bad.append(f"{widget_id}: missing {entry_point}")

if missing or bad:
  for item in missing:
    print(f"missing manifest for {item}", file=sys.stderr)
  for item in bad:
    print(item, file=sys.stderr)
  sys.exit(1)
PY
pass "default bar widget ids resolve to manifests and entry points"

migration=$(grep -rl 'Place the system update indicator next to weather in the bar' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "update placement migration exists"

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/home/.config/omarchy"

cat >"$TMPDIR/home/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [{ "id": "omarchy.menu" }, { "id": "omarchy.workspaces" }],
      "center": [{ "id": "omarchy.clock" }, { "id": "omarchy.weather" }],
      "right": [{ "id": "omarchy.tray" }, { "id": "omarchy.bluetooth" }]
    }
  },
  "plugins": []
}
JSON

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell append right omarchy.tailscale
jq -e '
  def ids: map(.id // .);
  .bar.layout.right | ids == ["omarchy.tray", "omarchy.tailscale", "omarchy.bluetooth"]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config appends right widgets after tray"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell append left local.left
jq -e '
  def ids: map(.id // .);
  .bar.layout.left | ids == ["omarchy.menu", "omarchy.workspaces", "local.left"]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config appends left widgets after workspaces"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell append center local.center
jq -e '
  def ids: map(.id // .);
  .bar.layout.center | ids == ["omarchy.clock", "omarchy.weather", "local.center"]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config appends center widgets after weather"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell prepend right local.first
jq -e '
  def ids: map(.id // .);
  .bar.layout.right | ids == ["local.first", "omarchy.tray", "omarchy.tailscale", "omarchy.bluetooth"]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config prepends widgets to section start"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell append right local.first
jq -e '
  def ids: map(.id // .);
  .bar.layout.right | ids == ["omarchy.tray", "local.first", "omarchy.tailscale", "omarchy.bluetooth"]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config moves existing widgets without duplicates"

cat >"$TMPDIR/home/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "bar": {
    "position": "top",
    "transparent": false,
    "centerAnchor": "omarchy.clock",
    "layout": {
      "left": [{ "id": "omarchy.menu" }],
      "center": [
        { "id": "omarchy.clock", "format": "HH:mm" },
        { "id": "omarchy.weather", "refreshMinutes": 30 },
        { "id": "omarchy.indicators", "items": ["Dnd", "NightLight"] },
        { "id": "omarchy.system-update", "custom": true }
      ],
      "right": [{ "id": "omarchy.audio" }]
    }
  },
  "plugins": [{ "id": "custom.plugin", "enabled": true }]
}
JSON

HOME="$TMPDIR/home" bash "$migration"

jq -e '
  def ids: map(.id // .);
  .bar.layout.center | ids == [
    "omarchy.clock",
    "omarchy.weather",
    "omarchy.system-update",
    "omarchy.indicators"
  ]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "update placement migration moves update after weather"

jq -e '
  .bar.layout.center[1].refreshMinutes == 30 and
  .bar.layout.center[2].custom == true and
  .bar.layout.center[3].items == ["Dnd", "NightLight"] and
  .plugins == [{ "id": "custom.plugin", "enabled": true }]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "update placement migration preserves unrelated settings"

before=$(sha256sum "$TMPDIR/home/.config/omarchy/shell.json" | awk '{print $1}')
HOME="$TMPDIR/home" bash "$migration"
after=$(sha256sum "$TMPDIR/home/.config/omarchy/shell.json" | awk '{print $1}')
[[ $before == "$after" ]] || fail "update placement migration is idempotent"
pass "update placement migration is idempotent"
