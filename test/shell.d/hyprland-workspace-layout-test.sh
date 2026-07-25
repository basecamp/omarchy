#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
log_file="$tmpdir/hyprctl.log"
mkdir -p "$stub_dir" "$home_dir"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash

if [[ $1 == "activeworkspace" && -n $HYPRCTL_BROKEN ]]; then
  printf '{}\n'
elif [[ $1 == "activeworkspace" ]]; then
  printf '{"id":3,"tiledLayout":"dwindle"}\n'
else
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
fi
EOF
chmod +x "$stub_dir/hyprctl"

cat >"$stub_dir/omarchy-notification-send" <<'EOF'
#!/bin/bash
:
EOF
chmod +x "$stub_dir/omarchy-notification-send"

HOME="$home_dir" HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" \
  "$ROOT/bin/omarchy-hyprland-workspace-layout-toggle"

layout_file="$home_dir/.local/state/omarchy/workspace-layouts/3.lua"
[[ -f $layout_file ]] || fail "workspace layout toggle saves a workspace rule"
grep -Fx 'hl.workspace_rule({ workspace = "3", layout = "scrolling" })' "$layout_file" >/dev/null ||
  fail "workspace layout toggle saves the selected layout"
grep -Fx 'eval hl.workspace_rule({ workspace = "3", layout = "scrolling" })' "$log_file" >/dev/null ||
  fail "workspace layout toggle applies the selected layout immediately"
pass "workspace layout toggle persists and applies the selected layout"

if HOME="$home_dir" HYPRCTL_LOG="$log_file" HYPRCTL_BROKEN=1 PATH="$stub_dir:$PATH" \
  "$ROOT/bin/omarchy-hyprland-workspace-layout-toggle" 2>/dev/null; then
  fail "workspace layout toggle exits nonzero without a workspace id"
fi
[[ -f "$home_dir/.local/state/omarchy/workspace-layouts/null.lua" ]] &&
  fail "workspace layout toggle does not persist a rule without a workspace id"
pass "workspace layout toggle ignores broken hyprctl output"

HOME="$home_dir" OMARCHY_PATH="$ROOT" lua <<'LUA'
local rules = {}

hl = {
  workspace_rule = function(rule)
    table.insert(rules, rule)
  end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.workspace-layouts")

assert(#rules == 1)
assert(rules[1].workspace == "3")
assert(rules[1].layout == "scrolling")
LUA
pass "saved workspace layouts load into Hyprland configuration"
