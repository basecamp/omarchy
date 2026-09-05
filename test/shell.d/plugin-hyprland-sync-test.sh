#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/.config/omarchy" "$TMPDIR/bin" "$TMPDIR/plugins"
calls="$TMPDIR/calls"

make_plugin() {
  local id="$1" priority="$2" deps="$3"
  local dir="$TMPDIR/plugins/$id"
  mkdir -p "$dir"
  cat >"$dir/manifest.json" <<JSON
{
  "schemaVersion": 1,
  "id": "$id",
  "name": "$id",
  "version": "1.0.0",
  "kinds": ["hyprland"],
  "entryPoints": {"hyprland": "plugin.lua"},
  "priority": $priority,
  "dependencies": $deps
}
JSON
  printf '%s\n' "-- $id" >"$dir/plugin.lua"
}

make_plugin "acme.dependency" 1 '[]'
make_plugin "acme.main" 50 '["acme.dependency"]'
make_plugin "acme.disabled" 0 '[]'

cat >"$TMPDIR/home/.config/omarchy/hypr-plugins.json" <<'JSON'
{"enabled":["acme.main"]}
JSON

cat >"$TMPDIR/bin/omarchy-plugin-list" <<'SH'
#!/bin/bash
cat <<'JSON'
[
  {"id":"acme.main","enabled":true,"kinds":["hyprland"]},
  {"id":"acme.disabled","enabled":false,"kinds":["hyprland"]},
  {"id":"acme.shell","enabled":true,"kinds":["service"]}
]
JSON
SH

cat >"$TMPDIR/bin/omarchy-plugin-catalog" <<CATALOG
#!/bin/bash
jq -n \
  --arg dep "$TMPDIR/plugins/acme.dependency" \
  --arg main "$TMPDIR/plugins/acme.main" \
  --arg disabled "$TMPDIR/plugins/acme.disabled" '
[
  {id:"acme.dependency", sourceDir:\$dep, kinds:["hyprland"], entryPoints:{hyprland:"plugin.lua"}, priority:1, dependencies:[]},
  {id:"acme.main", sourceDir:\$main, kinds:["hyprland"], entryPoints:{hyprland:"plugin.lua"}, priority:50, dependencies:["acme.dependency"]},
  {id:"acme.disabled", sourceDir:\$disabled, kinds:["hyprland"], entryPoints:{hyprland:"plugin.lua"}, priority:0, dependencies:[]}
]
'
CATALOG

cat >"$TMPDIR/bin/hyprctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
if [[ $1 == configerrors ]]; then
  printf 'no errors\n'
fi
SH

chmod +x "$TMPDIR/bin/omarchy-plugin-list" "$TMPDIR/bin/omarchy-plugin-catalog" "$TMPDIR/bin/hyprctl"

HOME="$TMPDIR/home" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_TEST_CALLS="$calls" \
  HYPRLAND_INSTANCE_SIGNATURE=test \
  PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
  omarchy-plugin-hyprland-sync >/dev/null

loader="$TMPDIR/home/.local/state/omarchy/hypr/plugins.lua"
[[ -f $loader ]] || fail "sync did not generate the Hyprland loader"

dependency_line=$(grep -n 'acme.dependency/plugin.lua' "$loader" | cut -d: -f1)
main_line=$(grep -n 'acme.main/plugin.lua' "$loader" | cut -d: -f1)
[[ $dependency_line -lt $main_line ]] || fail "dependencies do not load before dependents"
! grep -q 'acme.disabled/plugin.lua' "$loader" || fail "disabled Hyprland plugin was loaded"
grep -Fqx 'reload' "$calls" || fail "sync did not reload Hyprland"
grep -Fqx 'configerrors' "$calls" || fail "sync did not check Hyprland config errors"
pass "sync generates an ordered loader and reloads Hyprland"
