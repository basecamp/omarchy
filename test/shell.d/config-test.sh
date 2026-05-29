#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"

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

ROOT="$ROOT" python3 <<'PY'
import os
import sys
from pathlib import Path

root = Path(os.environ["ROOT"])
pkgbuild = (root.parent / "omarchy-pkgs/pkgbuilds/omarchy-settings/PKGBUILD").read_text()
omarchy_pkgbuild = (root.parent / "omarchy-pkgs/pkgbuilds/omarchy/PKGBUILD").read_text()
errors = []
package_defaults = [
  ("default/uwsm/env.d/10-omarchy", "/usr/share/uwsm/env.d/10-omarchy", "uwsm/env"),
  ("default/uwsm/default", None, "uwsm/default"),
  ("default/environment.d/10-omarchy-fcitx.conf", "/usr/lib/environment.d/10-omarchy-fcitx.conf", "environment.d/fcitx.conf"),
  ("default/fontconfig/conf.avail/30-omarchy.conf", "/usr/share/fontconfig/conf.avail/30-omarchy.conf", "fontconfig/fonts.conf"),
  ("default/xdg-terminal-exec/hyprland-xdg-terminals.list", "/usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list", "xdg-terminals.list"),
  ("default/applications/mimeapps.list", "/usr/share/applications/mimeapps.list", "mimeapps.list"),
  ("etc/fastfetch/config.jsonc", "/etc/fastfetch/config.jsonc", "fastfetch/config.jsonc"),
  ("default/systemd/user/bt-agent.service", "/usr/lib/systemd/user/bt-agent.service", "systemd/user/bt-agent.service"),
  ("default/systemd/user/omarchy-sleep-lock.service", "/usr/lib/systemd/user/omarchy-sleep-lock.service", "systemd/user/omarchy-sleep-lock.service"),
  ("default/systemd/user/omarchy-recover-internal-monitor.service", "/usr/lib/systemd/user/omarchy-recover-internal-monitor.service", "systemd/user/omarchy-recover-internal-monitor.service"),
  ("default/systemd/user/omarchy-update-user-notify.service", "/usr/lib/systemd/user/omarchy-update-user-notify.service", "systemd/user/omarchy-update-user-notify.service"),
  ("default/systemd/user/omarchy-update-user-notify.path", "/usr/lib/systemd/user/omarchy-update-user-notify.path", "systemd/user/omarchy-update-user-notify.path"),
  ("default/fonts/omarchy/omarchy.ttf", "/usr/share/fonts/omarchy/omarchy.ttf", "omarchy.ttf"),
]

for source, destination, legacy in package_defaults:
  if not (root / source).exists():
    errors.append(f"missing package default source: {source}")
  if (root / "config" / legacy).exists():
    errors.append(f"legacy path still in config/: {legacy}")
  if destination and (source not in pkgbuild or destination not in pkgbuild):
    errors.append(f"PKGBUILD does not explicitly install {source} -> {destination}")

guard_hook = "default/libalpm/hooks/00-omarchy-update-guard.hook"
guard_destination = "/usr/share/libalpm/hooks/00-omarchy-update-guard.hook"
if not (root / guard_hook).exists():
  errors.append(f"missing package default source: {guard_hook}")
if guard_hook not in omarchy_pkgbuild or guard_destination not in omarchy_pkgbuild:
  errors.append(f"omarchy PKGBUILD does not install {guard_hook} -> {guard_destination}")

if errors:
  print("\n".join(errors), file=sys.stderr)
  sys.exit(1)
PY
pass "package-owned defaults live outside config"

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

mapfile -t migrations < <(find "$ROOT/migrations" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort)
[[ ${#migrations[@]} -eq 0 ]] || fail "4.0 upgrade is not modeled as a migration"
pass "4.0 upgrade is handled outside the migration runner"
