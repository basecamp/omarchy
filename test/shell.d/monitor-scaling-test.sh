#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

export HOME="$tmp_dir/home"
export XDG_STATE_HOME="$tmp_dir/state"
mkdir -p "$HOME/.config/hypr" "$tmp_dir/bin"

cat >"$tmp_dir/bin/hyprctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$HYPRCTL_MONITORS_JSON"
EOF
chmod +x "$tmp_dir/bin/hyprctl"

monitors_json='[{"name":"eDP-1","focused":true,"scale":1.25,"width":1920,"height":1200,"refreshRate":144}]'

run_scaling() {
  PATH="$tmp_dir/bin:$PATH" HYPRCTL_MONITORS_JSON="$monitors_json" \
    "$ROOT/bin/omarchy-hyprland-monitor-scaling" "$1" 2>"$tmp_dir/err" \
    >"$tmp_dir/out"
}

# A customised monitors.lua with explicit per-output lines cannot be managed
# by the single-value persistence: the script's own sed would leave the
# explicit lines winning on the next reload, so the panel's change silently
# reverts. It must refuse loudly instead (issue #9950).
cat >"$HOME/.config/hypr/monitors.lua" <<'EOF'
local omarchy_monitor_scale = 1
hl.monitor({ output = "DP-1", mode = "preferred", position = "0x0", scale = 1 })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "1920x0", scale = 1.25 })
EOF

if run_scaling 1.6; then
  fail "customised monitors.lua makes scaling refuse"
fi
grep -q "cannot manage a customised monitors.lua" "$tmp_dir/err" ||
  fail "the refusal explains the customised file" "$(cat "$tmp_dir/err")"
pass "customised monitors.lua refuses with an explanation"

# A stock catch-all file keeps working exactly as before (persistence path).
cat >"$HOME/.config/hypr/monitors.lua" <<'EOF'
local omarchy_monitor_scale = 1.25
local omarchy_gdk_scale = 1
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
EOF
run_scaling 1.6
grep -q '^local omarchy_monitor_scale = 1.6$' "$HOME/.config/hypr/monitors.lua" ||
  fail "the stock catch-all still persists the new scale" \
    "$(cat "$HOME/.config/hypr/monitors.lua")"
pass "stock monitors.lua keeps persisting scales"

pass "scaling refuses on customised monitors.lua and keeps working on stock"
