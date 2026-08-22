#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
log_file="$tmpdir/hyprctl.log"
mkdir -p "$stub_dir"

# Workspaces 3, 4 and 7 are occupied on one monitor; 1, 2, 5 and 6 are holes.
cat >"$stub_dir/hyprctl" <<'EOF2'
#!/bin/bash

case "$1" in
  activeworkspace) printf '{"id":7}\n' ;;
  monitors) printf '[{"name":"eDP-1"}]\n' ;;
  workspaces)
    printf '[{"id":7,"monitor":"eDP-1","windows":1},{"id":3,"monitor":"eDP-1","windows":2},{"id":4,"monitor":"eDP-1","windows":1},{"id":-99,"monitor":"eDP-1","windows":1}]\n'
    ;;
  clients)
    printf '[{"address":"0xa","workspace":{"id":3}},{"address":"0xb","workspace":{"id":3}},{"address":"0xc","workspace":{"id":4}},{"address":"0xd","workspace":{"id":7}},{"address":"0xe","workspace":{"id":-99}}]\n'
    ;;
  dispatch) printf '%s\n' "$*" >>"$HYPRCTL_LOG" ;;
esac
EOF2
chmod +x "$stub_dir/hyprctl"

HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-compact"

grep -Fx 'dispatch hl.dsp.window.move({ window = "address:0xa", workspace = "1", follow = false })' "$log_file" >/dev/null ||
  fail "workspace compact moves the first occupied workspace to 1"
grep -Fx 'dispatch hl.dsp.window.move({ window = "address:0xb", workspace = "1", follow = false })' "$log_file" >/dev/null ||
  fail "workspace compact moves every window on a workspace"
grep -Fx 'dispatch hl.dsp.window.move({ window = "address:0xc", workspace = "2", follow = false })' "$log_file" >/dev/null ||
  fail "workspace compact fills the next free slot"
grep -Fx 'dispatch hl.dsp.window.move({ window = "address:0xd", workspace = "3", follow = false })' "$log_file" >/dev/null ||
  fail "workspace compact collapses across gaps"
grep -F '0xe' "$log_file" >/dev/null &&
  fail "workspace compact leaves special workspaces alone"
grep -Fx 'dispatch hl.dsp.focus({ workspace = "3" })' "$log_file" >/dev/null ||
  fail "workspace compact refocuses the active workspace at its new number"
pass "workspace compact collapses occupied workspaces to the lowest numbers"

: >"$log_file"
output=$(HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-compact" --dry-run)
[[ -s $log_file ]] && fail "workspace compact dry run does not dispatch"
grep -Fx 'workspace 7 -> 3 (eDP-1)' <<<"$output" >/dev/null || fail "workspace compact dry run prints the plan"
pass "workspace compact dry run only prints the plan"
