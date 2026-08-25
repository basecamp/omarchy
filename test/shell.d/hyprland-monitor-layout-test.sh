#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
source "$ROOT/bin/omarchy-hyprland-monitor-layout"

FIXTURES="$ROOT/test/shell.d/fixtures/monitor-layout"
CLI="$ROOT/bin/omarchy-hyprland-monitor-layout"

layout_is_internal "eDP-2" || fail "eDP-2 is internal"
layout_is_internal "DP-1" && fail "DP-1 is not internal"
pass "internal output names"

laptop=$(<"$FIXTURES/hypr-laptop-only.json")
got=$(layout_state_from_hypr "$laptop" false false)
[[ $(jq -r '.monitors[0].internal' <<<"$got") == "true" ]] || fail "laptop-only marks eDP internal"
[[ $(jq -r '.externalConnected' <<<"$got") == "false" ]] || fail "laptop-only has no external"
pass "state from laptop-only fixture"

pair=$(<"$FIXTURES/hypr-laptop-external.json")
got=$(layout_state_from_hypr "$pair" true false)
[[ $(jq -r '.monitors[1].internal' <<<"$got") == "false" ]] || fail "DP-1 is external"
[[ $(jq -r '.monitors[1].x' <<<"$got") == "1280" ]] || fail "DP-1 x from fixture"
pass "state from laptop+external fixture"

disabled=$(<"$FIXTURES/hypr-disabled.json")
got=$(layout_state_from_hypr "$disabled" true false)
[[ $(jq -r '.monitors[1].enabled' <<<"$got") == "false" ]] || fail "disabled HDMI"
pass "state from disabled fixture"

mirrored=$(<"$FIXTURES/hypr-mirror.json")
got=$(layout_state_from_hypr "$mirrored" true false)
[[ $(jq -r '.mirrorOn' <<<"$got") == "true" ]] || fail "mirror on"
pass "state from mirror fixture"

layout_is_laptop_only "$laptop" || fail "laptop-only detection"
layout_is_laptop_only "$pair" && fail "pair is not laptop-only"
pass "laptop-only detection"

ok='{"monitors":[{"name":"eDP-2","x":0,"y":0},{"name":"DP-1","x":1280,"y":0}]}'
layout_validate_apply "$pair" "$ok" || fail "valid side-by-side"
pass "validate side-by-side"

unknown='{"monitors":[{"name":"eDP-2","x":0,"y":0},{"name":"HDMI-A-9","x":1280,"y":0}]}'
if layout_validate_apply "$pair" "$unknown" 2>/tmp/layout-err; then
  fail "unknown output accepted"
fi
[[ $(cat /tmp/layout-err) == "unknown" ]] || fail "unknown stderr"
pass "reject unknown output"

overlap='{"monitors":[{"name":"eDP-2","x":0,"y":0},{"name":"DP-1","x":100,"y":0}]}'
if layout_validate_apply "$pair" "$overlap" 2>/tmp/layout-err; then
  fail "overlap accepted"
fi
[[ $(cat /tmp/layout-err) == "overlap" ]] || fail "overlap stderr"
pass "reject overlap"

island='{"monitors":[{"name":"eDP-2","x":0,"y":0},{"name":"DP-1","x":4000,"y":0}]}'
if layout_validate_apply "$pair" "$island" 2>/tmp/layout-err; then
  fail "island accepted"
fi
[[ $(cat /tmp/layout-err) == "disconnected" ]] || fail "disconnected stderr"
pass "reject disconnected"

omitted='{"monitors":[{"name":"eDP-2","x":0,"y":0}]}'
if layout_validate_apply "$pair" "$omitted" 2>/tmp/layout-err; then
  fail "omitted live monitor accepted"
fi
pass "reject omitted live monitor"

empty='{"monitors":[]}'
if layout_validate_apply "$pair" "$empty" 2>/tmp/layout-err; then
  fail "empty payload accepted"
fi
pass "reject empty payload"

chain='[
  {"name":"DP-1","width":100,"height":100,"refreshRate":60.0,"x":0,"y":0,"scale":1,"focused":true,"disabled":false,"mirrorOf":"none"},
  {"name":"DP-2","width":100,"height":100,"refreshRate":60.0,"x":100,"y":0,"scale":1,"focused":false,"disabled":false,"mirrorOf":"none"},
  {"name":"DP-3","width":100,"height":100,"refreshRate":60.0,"x":200,"y":0,"scale":1,"focused":false,"disabled":false,"mirrorOf":"none"}
]'
chain_apply='{"monitors":[{"name":"DP-1","x":0,"y":0},{"name":"DP-2","x":100,"y":0},{"name":"DP-3","x":200,"y":0}]}'
layout_validate_apply "$chain" "$chain_apply" || fail "3-monitor chain"
pass "validate 3-monitor chain"

apply='{"monitors":[{"name":"eDP-2","x":0,"y":0},{"name":"DP-1","x":1280,"y":0}]}'
got=$(layout_keyword_lines "$pair" "$apply")
want=$'eDP-2,2560x1600@165,0x0,2\nDP-1,2560x1440@144,1280x0,1'
[[ $got == "$want" ]] || fail "keyword lines" "got: $got"
pass "keyword lines"

block=$(layout_managed_block "$pair" "$apply")
[[ $(printf '%s\n' "$block" | head -n 1) == "$LAYOUT_START" ]] || fail "block start"
[[ $(printf '%s\n' "$block" | tail -n 1) == "$LAYOUT_END" ]] || fail "block end"
pass "managed block markers"

src=$(<"$FIXTURES/monitors.lua")
once=$(layout_patch_lua "$src" "$(layout_managed_block "$pair" "$apply")")
[[ $once == *"local omarchy_gdk_scale = 2"* ]] || fail "patch keeps GDK_SCALE"
[[ $once == *"leftover user comment"* ]] || fail "patch keeps user comment"
pass "first lua patch keeps surrounding text"

twice=$(layout_patch_lua "$once" "$(layout_managed_block "$pair" "$apply")")
start_count=$(grep -c -F -e "$LAYOUT_START" <<<"$twice")
[[ $start_count == "1" ]] || fail "second patch duplicates markers"
pass "second lua patch is idempotent"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
cp "$FIXTURES/monitors.lua" "$WORKDIR/monitors.lua"

export OMARCHY_MONITOR_LAYOUT_DRY_RUN=1
export OMARCHY_MONITOR_LAYOUT_MONITORS_JSON="$FIXTURES/hypr-laptop-only.json"
export OMARCHY_MONITOR_LAYOUT_EXTERNAL=false
export OMARCHY_MONITOR_LAYOUT_CLAMSHELL=false
export OMARCHY_MONITOR_LAYOUT_LUA_PATH="$WORKDIR/monitors.lua"

got=$("$CLI" state)
[[ $(jq -r '.externalConnected' <<<"$got") == "false" ]] || fail "cli state laptop"
pass "cli state"

apply_one='{"monitors":[{"name":"eDP-2","x":0,"y":0}]}'
"$CLI" apply "$apply_one" >/tmp/layout-apply-out
grep -q -F -e "$LAYOUT_START" "$WORKDIR/monitors.lua" && fail "laptop apply wrote lua"
pass "laptop apply is a no-op"

export OMARCHY_MONITOR_LAYOUT_MONITORS_JSON="$FIXTURES/hypr-laptop-external.json"
export OMARCHY_MONITOR_LAYOUT_EXTERNAL=true
apply_pair='{"monitors":[{"name":"eDP-2","x":0,"y":0},{"name":"DP-1","x":1280,"y":0}]}'
got=$("$CLI" apply "$apply_pair")
[[ $(jq -r '.keywords[1]' <<<"$got") == "DP-1,2560x1440@144,1280x0,1" ]] || fail "dry-run keyword"
grep -q -F -e "$LAYOUT_START" "$WORKDIR/monitors.lua" && fail "dry-run wrote lua"
pass "cli dry-run apply"

unset OMARCHY_MONITOR_LAYOUT_DRY_RUN
export OMARCHY_MONITOR_LAYOUT_WRITE_ONLY=1
"$CLI" apply "$apply_pair" >/dev/null
bak=$(find "$WORKDIR" -name 'monitors.lua.bak.*' | wc -l)
[[ $bak == "1" ]] || fail "first write backup count $bak"
"$CLI" apply "$apply_pair" >/dev/null
bak=$(find "$WORKDIR" -name 'monitors.lua.bak.*' | wc -l)
[[ $bak == "2" ]] || fail "second write backup count $bak"
pass "lua backups on write"

run_node_test <<'JS'
const model = requireFromRoot('shell/plugins/panels/monitor/Model.js')
assertDeepEqual(model.layoutSize(2560, 1600, 2), { w: 1280, h: 800 }, 'layout size divides by scale')

const laptop = { name: 'eDP-2', x: 0, y: 0, w: 1280, h: 800 }
const ext = { name: 'DP-1', x: 1400, y: 40, w: 2560, h: 1440 }
const snapped = model.snapPosition(ext, [laptop])
assertEqual(snapped.side, 'right', 'snap to right')
assertEqual(snapped.x, 1280, 'snap right x')

const above = model.snapPosition({ name: 'DP-1', x: 10, y: -900, w: 2560, h: 1440 }, [laptop])
assertEqual(above.side, 'top', 'snap to top')
assertEqual(above.y, -1440, 'snap top y')

const stacked = { name: 'DP-2', x: 1280, y: 0, w: 2560, h: 1440 }
const underCenter = model.snapWindows({ name: 'eDP-2', x: 1920, y: 1500, w: 1280, h: 800 }, [stacked])
assertEqual(underCenter.side, 'bottom', 'drop under center stays on bottom')
assertEqual(underCenter.x, 1920, 'drop under center keeps x')
assertEqual(underCenter.y, 1440, 'drop under center y')
JS
