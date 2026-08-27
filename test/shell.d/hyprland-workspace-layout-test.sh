#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
log_file="$tmpdir/hyprctl.log"
notify_file="$tmpdir/notify.log"
mkdir -p "$stub_dir" "$home_dir"

# The stub models the one behaviour the script has to cope with: `eval` answers
# ok whether or not the rule matched anything, so the layout only actually
# changes when the selector is the one Hyprland accepts. HYPRCTL_ACCEPTS names
# that selector; anything else is applied to nothing.
cat >"$stub_dir/hyprctl" <<'STUB'
#!/bin/bash

state="$HYPRCTL_STATE"
[[ -f $state ]] || printf '%s\n' "${HYPRCTL_LAYOUT:-dwindle}" >"$state"
layout=$(<"$state")

if [[ $1 == "activeworkspace" && -n $HYPRCTL_BROKEN ]]; then
  printf '{}\n'
elif [[ $1 == "activeworkspace" ]]; then
  # A second query can land after the user has switched away. Count calls so
  # the readback test can prove we do not re-query the active workspace.
  count_file="${state}.aw_count"
  count=0
  [[ -f $count_file ]] && count=$(<"$count_file")
  count=$((count + 1))
  printf '%s\n' "$count" >"$count_file"

  if [[ -n $HYPRCTL_SWITCHED ]] && (( count > 1 )); then
    printf '{"id":%s,"name":"%s","tiledLayout":"%s"}\n' \
      "${HYPRCTL_OTHER_ID:-1}" "${HYPRCTL_OTHER_NAME:-1}" "${HYPRCTL_OTHER_LAYOUT:-dwindle}"
  else
    printf '{"id":%s,"name":"%s","tiledLayout":"%s"}\n' \
      "${HYPRCTL_ID:-3}" "${HYPRCTL_NAME:-3}" "$layout"
  fi
elif [[ $1 == "workspaces" ]]; then
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
  printf '[{"id":%s,"name":"%s","tiledLayout":"%s"}' \
    "${HYPRCTL_ID:-3}" "${HYPRCTL_NAME:-3}" "$layout"
  if [[ -n $HYPRCTL_SWITCHED ]]; then
    printf ',{"id":%s,"name":"%s","tiledLayout":"%s"}' \
      "${HYPRCTL_OTHER_ID:-1}" "${HYPRCTL_OTHER_NAME:-1}" "${HYPRCTL_OTHER_LAYOUT:-dwindle}"
  fi
  printf ']\n'
else
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
  if [[ $1 == "eval" && -n $HYPRCTL_ACCEPTS && $* == *"workspace = \"$HYPRCTL_ACCEPTS\""* ]]; then
    printf '%s\n' "$(sed -n 's/.*layout = "\([^"]*\)".*/\1/p' <<<"$*")" >"$state"
  fi
  printf 'ok\n'
fi
STUB
chmod +x "$stub_dir/hyprctl"

cat >"$stub_dir/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUB
chmod +x "$stub_dir/omarchy-notification-send"

run_toggle() {
  env HOME="$home_dir" HYPRCTL_LOG="$log_file" NOTIFY_LOG="$notify_file" \
    PATH="$stub_dir:$PATH" "$@" "$ROOT/bin/omarchy-hyprland-workspace-layout-toggle"
}

# ── numeric workspace ────────────────────────────────────────────────────────
: >"$log_file"
: >"$notify_file"
run_toggle HYPRCTL_STATE="$tmpdir/s1" HYPRCTL_ID=3 HYPRCTL_NAME=3 HYPRCTL_ACCEPTS=3 ||
  fail "workspace layout toggle succeeds on a numeric workspace"

layout_file="$home_dir/.local/state/omarchy/workspace-layouts/3.lua"
[[ -f $layout_file ]] || fail "workspace layout toggle saves a workspace rule"
grep -Fx 'hl.workspace_rule({ workspace = "3", layout = "scrolling" })' "$layout_file" >/dev/null ||
  fail "workspace layout toggle saves the selected layout"
grep -Fx 'eval hl.workspace_rule({ workspace = "3", layout = "scrolling" })' "$log_file" >/dev/null ||
  fail "workspace layout toggle applies the selected layout immediately"
pass "workspace layout toggle persists and applies the selected layout"

# ── named workspace ──────────────────────────────────────────────────────────
# Hyprland gives these a negative id and reassigns it every session, so the id
# is useless as a selector and as a filename.
: >"$log_file"
: >"$notify_file"
run_toggle HYPRCTL_STATE="$tmpdir/s2" HYPRCTL_ID=-1340 HYPRCTL_NAME="DP-1 desk:1" \
  HYPRCTL_ACCEPTS="name:DP-1 desk:1" ||
  fail "workspace layout toggle succeeds on a named workspace"

grep -Fx 'eval hl.workspace_rule({ workspace = "name:DP-1 desk:1", layout = "scrolling" })' "$log_file" >/dev/null ||
  fail "workspace layout toggle addresses a named workspace by name"
named_file="$home_dir/.local/state/omarchy/workspace-layouts/name-DP-1_desk_1.lua"
[[ -f $named_file ]] ||
  fail "workspace layout toggle keys the saved rule on the name, not the reassigned id"
[[ -f "$home_dir/.local/state/omarchy/workspace-layouts/-1340.lua" ]] &&
  fail "workspace layout toggle does not key a named workspace on its id"
pass "workspace layout toggle handles named workspaces by name"

# ── a rule that matches nothing must not report success ──────────────────────
: >"$log_file"
: >"$notify_file"
if run_toggle HYPRCTL_STATE="$tmpdir/s3" HYPRCTL_ID=-1340 HYPRCTL_NAME="desk" HYPRCTL_ACCEPTS="never"; then
  fail "workspace layout toggle exits nonzero when the layout did not change"
fi
grep -q "Could not set workspace layout" "$notify_file" ||
  fail "workspace layout toggle reports a layout it could not apply"
grep -q "Workspace layout set to" "$notify_file" &&
  fail "workspace layout toggle does not claim success for a rule that matched nothing"
pass "workspace layout toggle reports a rule that applied to nothing"

# ── leftover id-keyed files are removed on upgrade ───────────────────────────
# require_all.files globs every *.lua. The leftover for this workspace is named
# after an id it no longer has; the file matching the current id usually
# belongs to a different workspace. Sweep every bare negative-id file.
: >"$log_file"
: >"$notify_file"
layouts_dir="$home_dir/.local/state/omarchy/workspace-layouts"
mkdir -p "$layouts_dir"
printf 'hl.workspace_rule({ workspace = "-1337", layout = "dwindle" })\n' >"$layouts_dir/-1337.lua"
printf 'hl.workspace_rule({ workspace = "-1340", layout = "dwindle" })\n' >"$layouts_dir/-1340.lua"
printf 'hl.workspace_rule({ workspace = "4", layout = "dwindle" })\n' >"$layouts_dir/4.lua"
rm -f "$named_file"
run_toggle HYPRCTL_STATE="$tmpdir/s4" HYPRCTL_ID=-1340 HYPRCTL_NAME="DP-1 desk:1" \
  HYPRCTL_ACCEPTS="name:DP-1 desk:1" ||
  fail "workspace layout toggle succeeds when replacing an id-keyed state file"
[[ -f $layouts_dir/-1337.lua ]] &&
  fail "workspace layout toggle removes this workspace's leftover id-keyed file"
[[ -f $layouts_dir/-1340.lua ]] &&
  fail "workspace layout toggle removes leftover files even when they match the current id"
[[ -f $layouts_dir/4.lua ]] ||
  fail "workspace layout toggle leaves numeric workspace files alone"
[[ -f $named_file ]] ||
  fail "workspace layout toggle still writes the name-based state file"
pass "workspace layout toggle removes leftover id-keyed state files"

# ── readback uses the named workspace, not a later active workspace ──────────
# If the user switches away between apply and readback, re-querying
# activeworkspace would read a different workspace and fail a change that
# worked.
: >"$log_file"
: >"$notify_file"
run_toggle HYPRCTL_STATE="$tmpdir/s5" HYPRCTL_ID=-1340 HYPRCTL_NAME="DP-1 desk:1" \
  HYPRCTL_ACCEPTS="name:DP-1 desk:1" HYPRCTL_SWITCHED=1 \
  HYPRCTL_OTHER_ID=7 HYPRCTL_OTHER_NAME=7 HYPRCTL_OTHER_LAYOUT=dwindle ||
  fail "workspace layout toggle still succeeds if the active workspace changes after apply"
grep -q "Could not set workspace layout" "$notify_file" &&
  fail "workspace layout toggle does not fail readback against a different workspace"
grep -q "Workspace layout set to scrolling" "$notify_file" ||
  fail "workspace layout toggle confirms the layout on the named workspace"
grep -F 'workspaces -j' "$log_file" >/dev/null ||
  fail "workspace layout toggle reads the layout back from the workspace list"
pass "workspace layout toggle reads back the named workspace after a switch"

# ── malformed hyprctl output ─────────────────────────────────────────────────
: >"$log_file"
if run_toggle HYPRCTL_STATE="$tmpdir/s6" HYPRCTL_BROKEN=1 2>/dev/null; then
  fail "workspace layout toggle exits nonzero without a workspace id"
fi
[[ -f "$home_dir/.local/state/omarchy/workspace-layouts/null.lua" ]] &&
  fail "workspace layout toggle does not persist a rule without a workspace id"
pass "workspace layout toggle ignores broken hyprctl output"

HOME="$home_dir" XDG_STATE_HOME="$home_dir/.local/state" OMARCHY_PATH="$ROOT" lua <<'LUA'
local rules = {}

hl = {
  workspace_rule = function(rule)
    table.insert(rules, rule)
  end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.workspace-layouts")

local seen = {}
for _, rule in ipairs(rules) do
  seen[rule.workspace] = rule.layout
end

assert(seen["3"] == "scrolling", "numeric workspace rule did not load")
assert(seen["name:DP-1 desk:1"] == "scrolling", "named workspace rule did not load")
assert(seen["-1340"] == nil, "stale id-keyed rule was not left behind")
LUA
pass "saved workspace layouts load into Hyprland configuration"
