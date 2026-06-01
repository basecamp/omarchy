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

jq -e '
  any(.bar.layout.center[]; (.id // .) == "omarchy.clock" and (.formatAlt // "") == "d MMMM \u0027W\u0027ww yyyy")
' "$ROOT/config/omarchy/shell.json" >/dev/null
pass "default clock date format has no leading zero"

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

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar add omarchy.tailscale
jq -e '
  def ids: map(.id // .);
  .bar.layout.right | ids == ["omarchy.tray", "omarchy.tailscale", "omarchy.bluetooth"]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config appends widgets to right by default"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar add local.left left
jq -e '
  def ids: map(.id // .);
  .bar.layout.left | ids == ["omarchy.menu", "omarchy.workspaces", "local.left"]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config appends left widgets after workspaces"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar add local.center center
jq -e '
  def ids: map(.id // .);
  .bar.layout.center | ids == ["omarchy.clock", "omarchy.weather", "local.center"]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config appends center widgets after weather"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar add local.first right
jq -e '
  def ids: map(.id // .);
  .bar.layout.right | ids == ["omarchy.tray", "local.first", "omarchy.tailscale", "omarchy.bluetooth"]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config moves existing widgets without duplicates"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar show | jq -e '
  def ids: map(.id // .);
  (.layout.right | ids == ["omarchy.tray", "local.first", "omarchy.tailscale", "omarchy.bluetooth"]) and
  has("version") | not
' >/dev/null
pass "shell config shows only bar json"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar list --json | jq -e '
  any(.[]; .id == "omarchy.system-stats" and .addable == true and .inBar == false) and
  all(.[]; .id != "omarchy.tailscale")
' >/dev/null
pass "shell config lists addable bar widgets"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar list --json --all | jq -e '
  any(.[]; .id == "omarchy.tailscale" and .inBar == true and .addable == false) and
  any(.[]; .id == "omarchy.indicators" and .addable == true)
' >/dev/null
pass "shell config list --all includes current widget status"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar position bottom
jq -e '
  .bar.position == "bottom" and
  .plugins == []
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config sets bar position"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar transparent true
jq -e '
  .bar.transparent == true and
  .bar.position == "bottom" and
  .plugins == []
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config sets bar transparency"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar drop local.left
jq -e '
  def ids: map(.id // .);
  (.bar.layout.left | ids == ["omarchy.menu", "omarchy.workspaces"]) and
  (.bar.layout.center | ids == ["omarchy.clock", "omarchy.weather", "local.center"]) and
  (.bar.layout.right | ids == ["omarchy.tray", "local.first", "omarchy.tailscale", "omarchy.bluetooth"])
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config drops widgets from any section"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-config-shell-bar remove local.center
jq -e '
  def ids: map(.id // .);
  .bar.layout.center | ids == ["omarchy.clock", "omarchy.weather"]
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config removes widgets with remove alias"

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

clock_migration=$(grep -rl 'Remove leading zero from bar clock date' "$ROOT/migrations" | head -n 1 || true)
[[ -n $clock_migration ]] || fail "clock date format migration exists"

cat >"$TMPDIR/home/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [],
      "center": [
        { "id": "omarchy.clock", "formatAlt": "dd MMMM 'W'ww yyyy" },
        { "id": "omarchy.weather" }
      ],
      "right": [
        { "id": "local.clock", "formatAlt": "dd MMMM 'W'ww yyyy" }
      ]
    }
  },
  "plugins": []
}
JSON

HOME="$TMPDIR/home" bash "$clock_migration"

jq -e '
  .bar.layout.center[0].formatAlt == "d MMMM \u0027W\u0027ww yyyy" and
  .bar.layout.right[0].formatAlt == "dd MMMM \u0027W\u0027ww yyyy"
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "clock date format migration removes leading zero from clock"

before=$(sha256sum "$TMPDIR/home/.config/omarchy/shell.json" | awk '{print $1}')
HOME="$TMPDIR/home" bash "$clock_migration"
after=$(sha256sum "$TMPDIR/home/.config/omarchy/shell.json" | awk '{print $1}')
[[ $before == "$after" ]] || fail "clock date format migration is idempotent"
pass "clock date format migration is idempotent"
