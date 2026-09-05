#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
runtime="$tmpdir/runtime"
mkdir -p "$runtime"
export XDG_RUNTIME_DIR="$runtime"

cat >"$tmpdir/hyprctl" <<'BASH'
#!/bin/bash

case "$1 $2" in
"activeworkspace -j")
  if [[ -n ${HYPR_SWITCH_COUNTER:-} ]]; then
    count=0
    [[ -f $HYPR_SWITCH_COUNTER ]] && count=$(<"$HYPR_SWITCH_COUNTER")
    count=$((count + 1))
    printf '%s\n' "$count" >"$HYPR_SWITCH_COUNTER"
    if ((count > ${HYPR_SWITCH_AFTER:-999999})); then
      printf '%s\n' '{"id":2,"name":"2","tiledLayout":"dwindle"}'
      exit 0
    fi
  fi

  if [[ -n ${HYPR_WORKSPACE:-} ]]; then
    printf '%s\n' "$HYPR_WORKSPACE"
  else
    printf '%s\n' '{"id":1,"name":"1","tiledLayout":"dwindle"}'
  fi
  ;;
"activewindow -j")
  if [[ -n ${HYPR_ACTIVE_WINDOW:-} ]]; then
    printf '%s\n' "$HYPR_ACTIVE_WINDOW"
  else
    printf '%s\n' '{"address":"0xa"}'
  fi
  ;;
"clients -j")
  printf '%s\n' "$HYPR_CLIENTS"
  ;;
"dispatch "*)
  printf '%s\n' "$2" >>"$HYPRCTL_LOG"
  if [[ -n ${HYPR_FAIL_ON_MATCH:-} && $2 == *"$HYPR_FAIL_ON_MATCH"* && ! -e ${HYPR_FAIL_MARKER:-/nonexistent} ]]; then
    touch "$HYPR_FAIL_MARKER"
    printf '%s\n' 'error: simulated dispatcher failure'
  else
    printf '%s\n' ok
  fi
  ;;
*)
  exit 1
  ;;
esac
BASH
chmod +x "$tmpdir/hyprctl"

cat >"$tmpdir/flock" <<'BASH'
#!/bin/bash

if [[ ${HYPR_FLOCK_FAIL:-false} == "true" ]]; then
  exit 1
fi
BASH
chmod +x "$tmpdir/flock"

clients='[
  {"address":"0xa","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[0,0]},
  {"address":"0xb","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[0,500]},
  {"address":"0xc","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[500,0]},
  {"address":"0xd","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[500,500]}
]'
log="$tmpdir/hyprctl.log"

unset_runtime_error="$tmpdir/unset-runtime-error"
if env -u XDG_RUNTIME_DIR PATH="$tmpdir:$PATH" HYPR_CLIENTS="$clients" HYPRCTL_LOG="$log" \
  "$ROOT/bin/omarchy-hyprland-window-equalize" 2>"$unset_runtime_error"; then
  fail "equalize refuses to use a shared temporary lock path without XDG_RUNTIME_DIR"
fi
grep -Fqx 'XDG_RUNTIME_DIR is required for window equalization' "$unset_runtime_error" ||
  fail "missing XDG_RUNTIME_DIR reports why equalization cannot start"
[[ ! -s $log ]] || fail "missing-runtime rejection happens before moving windows"
pass "equalize fails closed when XDG_RUNTIME_DIR is unavailable"

>"$log"

PATH="$tmpdir:$PATH" HYPR_CLIENTS="$clients" HYPRCTL_LOG="$log" \
  "$ROOT/bin/omarchy-hyprland-window-equalize"

(( $(grep -c 'workspace = "special:equalize-' "$log") == 4 )) ||
  fail "equalize moves every tiled window through a temporary workspace"
(( $(grep -c 'workspace = "name:1"' "$log") == 4 )) ||
  fail "equalize returns every tiled window to its original workspace"
(( $(grep -c 'hl.dsp.layout("preselect r")' "$log") == 1 )) ||
  fail "four-window grid creates two columns"
(( $(grep -c 'hl.dsp.layout("preselect d")' "$log") == 2 )) ||
  fail "four-window grid creates two rows per column"
(( $(grep -c 'hl.dsp.layout("splitratio 1' "$log") == 3 )) ||
  fail "four-window grid centers every split"
grep -Fqx 'hl.dsp.focus({ window = "address:0xa" })' "$log" ||
  fail "equalize restores the previously focused window"
pass "four tiled windows become an equal two-by-two grid"

clients='[
  {"address":"0xa","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[0,0]},
  {"address":"0xb","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[500,0]},
  {"address":"0xc","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[1000,0]}
]'
>"$log"

PATH="$tmpdir:$PATH" HYPR_CLIENTS="$clients" HYPRCTL_LOG="$log" \
  "$ROOT/bin/omarchy-hyprland-window-equalize"

(( $(grep -c 'hl.dsp.layout("preselect r")' "$log") == 2 )) ||
  fail "three-window grid creates three columns"
(( $(grep -c 'hl.dsp.layout("preselect d")' "$log" || true) == 0 )) ||
  fail "three-window grid does not create rows"
grep -Fqx 'hl.dsp.layout("splitratio 0.66666667 exact")' "$log" ||
  fail "three-window grid gives the first column one third of the width"
grep -Fqx 'hl.dsp.layout("splitratio 1.00000000 exact")' "$log" ||
  fail "three-window grid divides the remaining width equally"
pass "three tiled windows become three equal columns"

>"$log"
scrolling='{"id":1,"name":"1","tiledLayout":"scrolling"}'
if PATH="$tmpdir:$PATH" HYPR_CLIENTS="$clients" HYPRCTL_LOG="$log" HYPR_WORKSPACE="$scrolling" \
  "$ROOT/bin/omarchy-hyprland-window-equalize" 2>/dev/null; then
  fail "equalize rejects non-Dwindle workspaces"
fi
[[ ! -s $log ]] || fail "non-Dwindle rejection happens before moving windows"
pass "equalize rejects non-Dwindle workspaces before moving windows"

unsafe_clients='[
  {"address":"0xa","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":2,"fullscreenClient":2,"grouped":[],"at":[0,0]},
  {"address":"0xb","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[500,0]}
]'
>"$log"
if PATH="$tmpdir:$PATH" HYPR_CLIENTS="$unsafe_clients" HYPRCTL_LOG="$log" \
  "$ROOT/bin/omarchy-hyprland-window-equalize" 2>/dev/null; then
  fail "equalize rejects fullscreen tiled windows"
fi
[[ ! -s $log ]] || fail "fullscreen rejection happens before moving windows"
pass "equalize rejects fullscreen tiled windows before moving windows"

grouped_clients='[
  {"address":"0xa","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":["0xa","0xb"],"at":[0,0]},
  {"address":"0xb","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":["0xa","0xb"],"at":[500,0]}
]'
>"$log"
if PATH="$tmpdir:$PATH" HYPR_CLIENTS="$grouped_clients" HYPRCTL_LOG="$log" \
  "$ROOT/bin/omarchy-hyprland-window-equalize" 2>/dev/null; then
  fail "equalize rejects grouped tiled windows"
fi
[[ ! -s $log ]] || fail "grouped-window rejection happens before moving windows"
pass "equalize rejects grouped tiled windows before moving windows"

>"$log"
fail_marker="$tmpdir/dispatch-failed"
if PATH="$tmpdir:$PATH" HYPR_CLIENTS="$clients" HYPRCTL_LOG="$log" \
  HYPR_FAIL_ON_MATCH='preselect r' HYPR_FAIL_MARKER="$fail_marker" \
  "$ROOT/bin/omarchy-hyprland-window-equalize" 2>/dev/null; then
  fail "equalize reports a dispatcher failure"
fi
for address in 0xa 0xb 0xc; do
  grep -Fq "window = \"address:$address\", workspace = \"name:1\"" "$log" ||
    fail "failed equalize returns $address to the original workspace"
done
grep -Fqx 'hl.dsp.focus({ window = "address:0xa" })' "$log" ||
  fail "failed equalize restores the original focus"
pass "dispatcher failure rolls every window back to the original workspace"

>"$log"
switch_counter="$tmpdir/workspace-queries"
if PATH="$tmpdir:$PATH" HYPR_CLIENTS="$clients" HYPRCTL_LOG="$log" \
  HYPR_SWITCH_COUNTER="$switch_counter" HYPR_SWITCH_AFTER=3 \
  "$ROOT/bin/omarchy-hyprland-window-equalize" 2>/dev/null; then
  fail "equalize aborts when the active workspace changes"
fi
grep -Fqx 'hl.dsp.focus({ workspace = "name:1" })' "$log" ||
  fail "workspace-switch rollback returns to the original workspace"
pass "workspace switch aborts equalization and rolls windows back"

>"$log"
if PATH="$tmpdir:$PATH" HYPR_CLIENTS="$clients" HYPRCTL_LOG="$log" XDG_RUNTIME_DIR="$runtime" HYPR_FLOCK_FAIL=true \
  "$ROOT/bin/omarchy-hyprland-window-equalize" 2>/dev/null; then
  fail "equalize rejects a concurrent run"
fi
[[ ! -s $log ]] || fail "concurrent-run rejection happens before moving windows"
pass "equalize rejects concurrent runs across workspaces"

five_clients='[
  {"address":"0xa","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[0,0]},
  {"address":"0xb","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[0,500]},
  {"address":"0xc","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[500,0]},
  {"address":"0xd","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[500,500]},
  {"address":"0xe","workspace":{"id":1},"mapped":true,"floating":false,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[1000,0]},
  {"address":"0xf","workspace":{"id":1},"mapped":true,"floating":true,"fullscreen":0,"fullscreenClient":0,"grouped":[],"at":[200,200]}
]'
>"$log"
PATH="$tmpdir:$PATH" HYPR_CLIENTS="$five_clients" HYPRCTL_LOG="$log" XDG_RUNTIME_DIR="$runtime" \
  "$ROOT/bin/omarchy-hyprland-window-equalize"

(( $(grep -c 'workspace = "special:equalize-' "$log") == 5 )) ||
  fail "five-window grid moves only the five tiled windows"
! grep -Fq 'address:0xf' "$log" || fail "equalize leaves floating windows untouched"
(( $(grep -c 'hl.dsp.layout("preselect r")' "$log") == 2 )) ||
  fail "five-window grid creates three columns"
(( $(grep -c 'hl.dsp.layout("preselect d")' "$log") == 2 )) ||
  fail "five-window grid creates two stacked columns"
grep -Fqx 'hl.dsp.layout("splitratio 0.80000000 exact")' "$log" ||
  fail "five-window grid sizes the first column by its window count"
grep -Fqx 'hl.dsp.layout("splitratio 1.33333333 exact")' "$log" ||
  fail "five-window grid sizes the second column by its window count"
pass "five tiled windows receive equal areas while floating windows stay untouched"

>"$log"
PATH="$tmpdir:$PATH" HYPR_CLIENTS="$five_clients" HYPRCTL_LOG="$log" HYPR_ACTIVE_WINDOW='{"address":"0xf"}' \
  "$ROOT/bin/omarchy-hyprland-window-equalize"
mapfile -t dispatches <"$log"
last_dispatch=${dispatches[${#dispatches[@]} - 1]}
[[ $last_dispatch == 'hl.dsp.focus({ window = "address:0xf" })' ]] ||
  fail "equalize restores focus to an untouched floating window"
pass "equalize preserves focus on an untouched floating window"

>"$log"
PATH="$tmpdir:$PATH" HYPR_CLIENTS="$clients" HYPRCTL_LOG="$log" HYPR_ACTIVE_WINDOW='{}' \
  "$ROOT/bin/omarchy-hyprland-window-equalize"
! grep -Fq 'window = "address:"' "$log" ||
  fail "equalize never dispatches an empty focus selector"
grep -Fqx 'hl.dsp.focus({ window = "address:0xa" })' "$log" ||
  fail "equalize falls back to the first tiled window when focus has no address"
pass "missing active-window address falls back to the first tiled window"

grep -Fqx 'o.bind("SUPER + E", "Equalize tiled windows", "omarchy-hyprland-window-equalize")' \
  "$ROOT/default/hypr/bindings/tiling.lua" ||
  fail "Super + E exposes equalize in the default keybindings"
pass "Super + E exposes equalize in the default keybindings"
