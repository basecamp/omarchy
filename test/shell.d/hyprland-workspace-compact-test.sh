#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
log_file="$tmpdir/hyprctl.log"
mkdir -p "$stub_dir"

# Workspaces 3, 4 and 7 are occupied on one monitor; 1, 2, 5 and 6 are holes.
# Workspace 9 is named and must be left alone. CHANGE_ID_FAILS makes the Lua
# change_id dispatcher fail so the window-move fallback is exercised.
cat >"$stub_dir/hyprctl" <<'EOF2'
#!/bin/bash

case "$1" in
  activeworkspace) printf '{"id":7}\n' ;;
  monitors) printf '[{"name":"eDP-1"}]\n' ;;
  workspaces)
    printf '[{"id":7,"name":"7","monitor":"eDP-1","windows":1},{"id":3,"name":"3","monitor":"eDP-1","windows":2},{"id":4,"name":"4","monitor":"eDP-1","windows":1},{"id":9,"name":"mail","monitor":"eDP-1","windows":1},{"id":-99,"name":"special:scratchpad","monitor":"eDP-1","windows":1}]\n'
    ;;
  clients)
    printf '[{"address":"0xa","workspace":{"id":3}},{"address":"0xb","workspace":{"id":3}},{"address":"0xc","workspace":{"id":4}},{"address":"0xd","workspace":{"id":7}},{"address":"0xe","workspace":{"id":-99}},{"address":"0xf","workspace":{"id":9}}]\n'
    ;;
  dispatch)
    printf '%s\n' "$*" >>"$HYPRCTL_LOG"
    if [[ -n $CHANGE_ID_FAILS && $2 == *change_id* ]]; then exit 1; fi
    ;;
esac
exit 0
EOF2
chmod +x "$stub_dir/hyprctl"

HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-compact"

grep -Fx 'dispatch hl.dsp.workspace.change_id({ workspace = "3", id = 1 })' "$log_file" >/dev/null ||
  fail "workspace compact renumbers the first occupied workspace to 1 with change_id"
grep -Fx 'dispatch hl.dsp.workspace.change_id({ workspace = "4", id = 2 })' "$log_file" >/dev/null ||
  fail "workspace compact fills the next free slot"
grep -Fx 'dispatch hl.dsp.workspace.change_id({ workspace = "7", id = 3 })' "$log_file" >/dev/null ||
  fail "workspace compact collapses across gaps"
grep -F 'window.move' "$log_file" >/dev/null &&
  fail "workspace compact does not move windows when change_id succeeds"
grep -F '0xe' "$log_file" >/dev/null &&
  fail "workspace compact leaves special workspaces alone"
grep -F '"9"' "$log_file" >/dev/null &&
  fail "workspace compact leaves named workspaces alone"
grep -Fx 'dispatch hl.dsp.focus({ workspace = "3" })' "$log_file" >/dev/null ||
  fail "workspace compact refocuses the active workspace at its new number"
pass "workspace compact renumbers occupied workspaces to the lowest numbers"

: >"$log_file"
CHANGE_ID_FAILS=1 HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-compact"
grep -Fx 'dispatch hl.dsp.window.move({ window = "address:0xa", workspace = "1", follow = false })' "$log_file" >/dev/null ||
  fail "workspace compact falls back to moving windows"
grep -Fx 'dispatch hl.dsp.window.move({ window = "address:0xb", workspace = "1", follow = false })' "$log_file" >/dev/null ||
  fail "workspace compact moves every window on the workspace"
grep -Fx 'dispatch hl.dsp.workspace.move({ workspace = "1", monitor = "eDP-1" })' "$log_file" >/dev/null ||
  fail "workspace compact pins the fallback target to the original monitor"
pass "workspace compact falls back to window moves when change_id is unavailable"

: >"$log_file"
output=$(HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-compact" --dry-run)
[[ -s $log_file ]] && fail "workspace compact dry run does not dispatch"
grep -Fx 'workspace 7 -> 3 (eDP-1)' <<<"$output" >/dev/null || fail "workspace compact dry run prints the plan"
pass "workspace compact dry run only prints the plan"

HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-compact" --help >/dev/null ||
  fail "workspace compact --help exits 0"
HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-compact" --bogus >/dev/null 2>&1 &&
  fail "workspace compact unknown flags must not compact"
pass "workspace compact rejects unknown flags"

# A named workspace occupying id 2 (renameworkspace) must not be a landing slot.
cat >"$stub_dir/hyprctl" <<'EOF2'
#!/bin/bash
case "$1" in
  activeworkspace) printf '{"id":3}\n' ;;
  monitors) printf '[{"name":"eDP-1"}]\n' ;;
  workspaces)
    printf '[{"id":2,"name":"mail","monitor":"eDP-1","windows":1},{"id":3,"name":"3","monitor":"eDP-1","windows":1},{"id":4,"name":"4","monitor":"eDP-1","windows":1}]\n'
    ;;
  clients)
    printf '[{"address":"0xmail","workspace":{"id":2}},{"address":"0xa","workspace":{"id":3}},{"address":"0xb","workspace":{"id":4}}]\n'
    ;;
  dispatch) printf '%s\n' "$*" >>"$HYPRCTL_LOG" ;;
esac
exit 0
EOF2
: >"$log_file"
HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-compact"
grep -Fx 'dispatch hl.dsp.workspace.change_id({ workspace = "3", id = 1 })' "$log_file" >/dev/null ||
  fail "workspace compact packs around a named workspace occupying a low id"
grep -E 'id = 2' "$log_file" >/dev/null &&
  fail "workspace compact must not land on a named workspace's id"
grep -F '0xmail' "$log_file" >/dev/null &&
  fail "workspace compact must not move windows onto a named workspace"
pass "workspace compact skips named-workspace ids when packing"
