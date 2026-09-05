#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"

require_command jq
require_command lua
require_command python3

jq empty "$ROOT/config/omarchy/shell.json"
pass "default shell.json is valid JSON"

jq -e '.version == 1 and (.bar.layout.left | type == "array") and (.bar.layout.center | type == "array") and (.bar.layout.right | type == "array")' "$ROOT/config/omarchy/shell.json" >/dev/null
pass "default shell.json has versioned bar layout"

# Pinning the whole row made this fail every time an unrelated widget moved,
# so assert the adjacency the name is about and let the rest of the row change.
jq -e '
  def ids: map(.id // .);
  (.bar.layout.center | ids) as $ids |
  ($ids | index("omarchy.weather")) as $weather |
  ($ids | index("omarchy.system-update")) as $update |
  $weather != null and $update == $weather + 1
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

jq -e '
  def ids: map(.id // .);
  (.bar.layout.right | ids) as $ids |
  ($ids | index("omarchy.tray")) as $tray |
  ($ids | index("omarchy.agents")) as $agents |
  $tray != null and $agents == $tray + 1
' "$ROOT/config/omarchy/shell.json" >/dev/null
pass "default right layout keeps agents next to the tray"

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
home = Path.home()
pkgs_candidates = [
  root.parent / "omarchy-pkgs/pkgbuilds",
  root.parent / "omarchy/omarchy-pkgs/pkgbuilds",
  root.parent.parent / "omarchy-pkgs/pkgbuilds",
  root.parent / "omacom/omarchy-pkgs/pkgbuilds",
  root.parent.parent / "omacom/omarchy-pkgs/pkgbuilds",
  home / "Work/omacom/omarchy-pkgs/pkgbuilds",
]
# Checkouts differ per machine, so allow an explicit pointer at the sibling repo.
# Accepts either the omarchy-pkgs checkout or its pkgbuilds/ directory.
override = os.environ.get("OMARCHY_PKGS_PATH")
if override:
  pkgs_candidates = [Path(override) / "pkgbuilds", Path(override)] + pkgs_candidates
pkgs_root = next((path for path in pkgs_candidates if path.exists()), None)
if pkgs_root is None:
  print("not ok - omarchy-pkgs checkout found for PKGBUILD coverage", file=sys.stderr)
  print(
    "looked in:\n  " + "\n  ".join(str(path) for path in pkgs_candidates) +
    "\nset OMARCHY_PKGS_PATH to the omarchy-pkgs checkout",
    file=sys.stderr,
  )
  sys.exit(1)
settings_pkgbuild_path = pkgs_root / "omarchy-settings/PKGBUILD"
omarchy_pkgbuild_path = pkgs_root / "omarchy/PKGBUILD"
if not settings_pkgbuild_path.exists():
  settings_pkgbuild_path = pkgs_root / "omarchy-settings-dev/PKGBUILD"
if not omarchy_pkgbuild_path.exists():
  omarchy_pkgbuild_path = pkgs_root / "omarchy-dev/PKGBUILD"
pkgbuild = settings_pkgbuild_path.read_text()
omarchy_pkgbuild = omarchy_pkgbuild_path.read_text()
errors = []
package_defaults = [
  ("default/uwsm/env.d/10-omarchy", "/usr/share/uwsm/env.d/10-omarchy", "uwsm/env"),
  ("default/uwsm/default", None, "uwsm/default"),
  ("default/environment.d/10-omarchy-fcitx.conf", "/usr/lib/environment.d/10-omarchy-fcitx.conf", "environment.d/fcitx.conf"),
  ("default/fontconfig/conf.avail/50-omarchy.conf", "/usr/share/fontconfig/conf.avail/50-omarchy.conf", "fontconfig/fonts.conf"),
  ("default/xdg-terminal-exec/hyprland-xdg-terminals.list", "/usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list", "xdg-terminals.list"),
  ("default/applications/mimeapps.list", "/usr/share/applications/mimeapps.list", "mimeapps.list"),
  ("etc/fastfetch/config.jsonc", "/etc/fastfetch/config.jsonc", "fastfetch/config.jsonc"),
  ("default/systemd/user/bt-agent.service", "/usr/lib/systemd/user/bt-agent.service", "systemd/user/bt-agent.service"),
  ("default/systemd/user/omarchy-sleep-lock.service", "/usr/lib/systemd/user/omarchy-sleep-lock.service", "systemd/user/omarchy-sleep-lock.service"),
  ("default/systemd/user/omarchy-recover-internal-monitor.service", "/usr/lib/systemd/user/omarchy-recover-internal-monitor.service", "systemd/user/omarchy-recover-internal-monitor.service"),
  ("default/systemd/user/omarchy-migrate-notify.service", "/usr/lib/systemd/user/omarchy-migrate-notify.service", "systemd/user/omarchy-migrate-notify.service"),
  ("default/systemd/user/omarchy-tailscale-receive.service", "/usr/lib/systemd/user/omarchy-tailscale-receive.service", "systemd/user/omarchy-tailscale-receive.service"),
  ("default/systemd/user/omarchy-fcitx5.service", "/usr/lib/systemd/user/omarchy-fcitx5.service", "systemd/user/omarchy-fcitx5.service"),
  ("default/systemd/user/omarchy-crash-watch.service", "/usr/lib/systemd/user/omarchy-crash-watch.service", "systemd/user/omarchy-crash-watch.service"),
  ("default/systemd/zram-generator.conf.d/90-omarchy.conf", "/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf", "systemd/zram-generator.conf.d/90-omarchy.conf"),
  ("default/fonts/omarchy/omarchy.ttf", "/usr/share/fonts/omarchy/omarchy.ttf", "omarchy.ttf"),
  ("default/snapper/root", "/etc/snapper/config-templates/omarchy", "snapper/root"),
]

for source, destination, legacy in package_defaults:
  if not (root / source).exists():
    errors.append(f"missing package default source: {source}")
  if (root / "config" / legacy).exists():
    errors.append(f"legacy path still in config/: {legacy}")
  if destination and (source not in pkgbuild or destination not in pkgbuild):
    errors.append(f"PKGBUILD does not explicitly install {source} -> {destination}")

# Existing users have an absolute wants symlink to the old unit path, and the
# migration that repoints it only runs for users who run an update -- the
# opposite of who the notifier is for. Dropping this alias strands them.
notify_alias = 'ln -sfn omarchy-migrate-notify.service "$pkgdir/usr/lib/systemd/user/omarchy-update-user-notify.service"'
if notify_alias not in pkgbuild:
  errors.append(
    "PKGBUILD does not ship the omarchy-update-user-notify.service compatibility "
    "alias, so users who have not run migration 1785095882 lose the login notifier"
  )

alpm_hooks = [
  "00-omarchy-update-guard.hook",
  "10-omarchy-hyprland-reload-pause.hook",
  "90-omarchy-hyprland-reload-resume.hook",
]
for hook in alpm_hooks:
  source = f"default/libalpm/hooks/{hook}"
  destination = f"/usr/share/libalpm/hooks/{hook}"
  if not (root / source).exists():
    errors.append(f"missing package default source: {source}")
  if source not in omarchy_pkgbuild or destination not in omarchy_pkgbuild:
    errors.append(f"omarchy PKGBUILD does not install {source} -> {destination}")

if errors:
  print("\n".join(errors), file=sys.stderr)
  sys.exit(1)
PY
pass "package-owned defaults live outside config"

grep -F 'dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")' "$ROOT/config/hypr/hyprland.lua" >/dev/null
grep -F 'require("default.hypr.omarchy")' "$ROOT/config/hypr/hyprland.lua" >/dev/null
grep -F 'package.path = home' "$ROOT/default/hypr/bootstrap.lua" >/dev/null
grep -F '/.local/state/?.lua;' "$ROOT/default/hypr/bootstrap.lua" >/dev/null
pass "Hyprland user entrypoint keeps package and state path bootstrap in defaults"

OMARCHY_PATH="$ROOT" lua <<'LUA'
package.loaded["default.hypr.omarchy"] = true
package.loaded["default.hypr.require_optional"] = true
package.loaded["hypr.looknfeel"] = true
package.loaded["omarchy.current.theme.hyprland"] = true
package.loaded["unrelated.module"] = true

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")

assert(package.loaded["default.hypr.omarchy"] == nil)
assert(package.loaded["default.hypr.require_optional"] == nil)
assert(package.loaded["hypr.looknfeel"] == nil)
assert(package.loaded["omarchy.current.theme.hyprland"] == nil)
assert(package.loaded["unrelated.module"] == true)
LUA
pass "Hyprland bootstrap reloads cached Omarchy config modules"

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/home/.config/omarchy"

ipc_mock_bin="$TMPDIR/ipc-mock"
mkdir -p "$ipc_mock_bin"
cat >"$ipc_mock_bin/omarchy-shell" <<'SH'
#!/bin/bash
set -euo pipefail

mkdir -p "$HOME/.local/state/omarchy"
printf '%s\n' "$*" >>"$HOME/.local/state/omarchy/shell-ipc-calls"
printf 'ok\n'
SH
chmod +x "$ipc_mock_bin/omarchy-shell"
export PATH="$ipc_mock_bin:$PATH"

cat >"$TMPDIR/home/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [{ "id": "omarchy.menu" }, { "id": "omarchy.workspaces" }, { "id": "omarchy.active-window" }],
      "center": [{ "id": "omarchy.clock" }, { "id": "omarchy.weather" }, { "id": "omarchy.system-update" }, { "id": "omarchy.tailscale" }],
      "right": [{ "id": "omarchy.tray" }, { "id": "omarchy.microphone" }, { "id": "omarchy.bluetooth" }]
    }
  },
  "plugins": []
}
JSON

mkdir -p "$TMPDIR/home/.config/omarchy/plugins/local.demo-bar"
cat >"$TMPDIR/home/.config/omarchy/plugins/local.demo-bar/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "local.demo-bar",
  "name": "Demo bar",
  "version": "1.0.0",
  "author": "Test",
  "description": "Replacement bar for config tests",
  "kinds": ["bar"],
  "entryPoints": { "bar": "Bar.qml" }
}
JSON
touch "$TMPDIR/home/.config/omarchy/plugins/local.demo-bar/Bar.qml"

if HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar use local.nonexistent-bar 2>/dev/null; then
  fail "bar use accepted an unknown bar option"
fi
pass "bar use rejects an unknown bar option"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar use local.demo-bar
jq -e '.bar.id == "local.demo-bar"' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config selects a bar option"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar reset
jq -e '.bar.id == null' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config resets to built-in bar option"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar move omarchy.active-window right
grep -Fqx 'shell moveBarWidget omarchy.active-window {"section":"right"}' \
  "$TMPDIR/home/.local/state/omarchy/shell-ipc-calls"
pass "bar move accepts a positional target section"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar move omarchy.active-window left
grep -Fqx 'shell moveBarWidget omarchy.active-window {"section":"left"}' \
  "$TMPDIR/home/.local/state/omarchy/shell-ipc-calls"
pass "bar move can restore a widget with positional syntax"

if HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar move omarchy.active-window left --section right 2>/dev/null; then
  fail "bar move accepted positional and flagged target sections"
fi
pass "bar move rejects conflicting target section syntax"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar position bottom
jq -e '
  .bar.position == "bottom" and
  .plugins == []
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config sets bar position"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar transparent true
jq -e '
  .bar.transparent == true and
  .bar.position == "bottom" and
  .plugins == []
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config sets bar transparency"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar transparent toggle
jq -e '.bar.transparent == false' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell config toggles bar transparency"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar set omarchy.bluetooth enabled false --json
grep -Fqx 'shell setBarWidget omarchy.bluetooth enabled false {}' \
  "$TMPDIR/home/.local/state/omarchy/shell-ipc-calls"
pass "bar set accepts false JSON values"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar set omarchy.bluetooth optional null --json
grep -Fqx 'shell setBarWidget omarchy.bluetooth optional null {}' \
  "$TMPDIR/home/.local/state/omarchy/shell-ipc-calls"
pass "bar set accepts null JSON values"

if HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar set omarchy.bluetooth broken '{' --json 2>/dev/null; then
  fail "bar set accepted malformed JSON"
fi
pass "bar set rejects malformed JSON"

if HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" omarchy-bar set omarchy.bluetooth broken 'false null' --json 2>/dev/null; then
  fail "bar set accepted multiple JSON values"
fi
pass "bar set rejects multiple JSON values"

mock_bin="$TMPDIR/mock-bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-refresh-config" <<'SH'
#!/bin/bash
set -euo pipefail

relative_path="${1:-}"
[[ -n $relative_path ]] || exit 1
mkdir -p "$HOME/.config/$(dirname "$relative_path")"
cp "$OMARCHY_PATH/config/$relative_path" "$HOME/.config/$relative_path"
SH

cat >"$mock_bin/omarchy-restart-shell" <<'SH'
#!/bin/bash
set -euo pipefail

mkdir -p "$HOME/.local/state/omarchy"
touch "$HOME/.local/state/omarchy/restart-shell-called"
SH

cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_SHELL_DOWN:-0} == "1" ]] && exit 1
printf 'ok\n'
SH

cat >"$mock_bin/omarchy-installed-service-dropbox" <<'SH'
#!/bin/bash
set -euo pipefail

[[ ${OMARCHY_TEST_DROPBOX:-0} == "1" ]]
SH

cat >"$mock_bin/omarchy-installed-service-tailscale" <<'SH'
#!/bin/bash
set -euo pipefail

[[ ${OMARCHY_TEST_TAILSCALE:-0} == "1" ]]
SH

chmod +x "$mock_bin"/*
mock_path="$mock_bin:$ROOT/bin:$PATH"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" PATH="$mock_path" OMARCHY_TEST_DROPBOX=0 OMARCHY_TEST_TAILSCALE=0 omarchy-bar defaults
jq -e --slurpfile defaults "$ROOT/config/omarchy/shell.json" '
  .bar == $defaults[0].bar and
  .plugins == []
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "bar defaults restores the stock bar"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" PATH="$mock_path" OMARCHY_TEST_DROPBOX=1 OMARCHY_TEST_TAILSCALE=1 omarchy-bar defaults
jq -e '
  def ids: map(.id // .);
  (.bar.layout.right | ids) as $right |
  ($right | index("omarchy.tray")) as $tray |
  ($right | index("omarchy.tailscale") == $tray + 1) and
  ($right | index("omarchy.dropbox") == $tray + 2) and
  (.bar.layout.center | ids | index("omarchy.tailscale") == null)
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "bar defaults places plugins for running optional services"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" PATH="$mock_path" \
  OMARCHY_TEST_SHELL_DOWN=1 OMARCHY_TEST_DROPBOX=1 OMARCHY_TEST_TAILSCALE=1 \
  omarchy-bar defaults
jq -e '
  def ids: map(.id // .);
  (.bar.layout.right | ids) as $right |
  ($right | index("omarchy.tray")) as $tray |
  ($right | index("omarchy.tailscale") == $tray + 1) and
  ($right | index("omarchy.dropbox") == $tray + 2) and
  (.bar.layout.center | ids | index("omarchy.tailscale") == null)
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "bar defaults places service widgets without a running shell"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" PATH="$mock_path" OMARCHY_TEST_DROPBOX=0 OMARCHY_TEST_TAILSCALE=0 omarchy-refresh-shell
jq -e '
  def ids: map(.id // .);
  ([.bar.layout.left, .bar.layout.center, .bar.layout.right] | map(ids) | add) as $all |
  ($all | index("omarchy.dropbox") == null) and
  ($all | index("omarchy.tailscale") == null)
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
pass "shell refresh keeps optional service widgets absent when services are unavailable"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" PATH="$mock_path" OMARCHY_TEST_DROPBOX=1 OMARCHY_TEST_TAILSCALE=1 omarchy-refresh-shell
jq -e '
  def ids: map(.id // .);
  (.bar.layout.right | ids) as $right |
  ($right | index("omarchy.tray")) as $tray |
  ($right | index("omarchy.tailscale") == $tray + 1) and
  ($right | index("omarchy.dropbox") == $tray + 2) and
  (.bar.layout.center | ids | index("omarchy.tailscale") == null)
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null
[[ -f $TMPDIR/home/.local/state/omarchy/restart-shell-called ]] || fail "shell refresh restarts shell"
pass "shell refresh places optional service widgets when services are available"

if grep -RIl 'upgrade-to-quattro\|Omarchy 4\.0 is upgraded' "$ROOT/migrations" >/dev/null; then
  fail "4.0 upgrade is not modeled as a migration"
fi
pass "4.0 upgrade is handled outside the migration runner"
