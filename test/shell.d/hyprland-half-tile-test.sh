#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
mkdir -p "$home/.local/state/omarchy/toggles/hypr" "$home/.config"

run_half_tile() {
  local prelude="${1:-}"

  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" \
    OMARCHY_PATH="$ROOT" OMARCHY_HALF_TILE_PRELUDE="$prelude" lua - <<'LUA' || return 1
local rules, handlers, configs = {}, {}, {}
local monitors, workspaces, windows = {}, {}, {}
local active_workspace, special_workspace = nil, nil
local gaps = { top = 10, right = 10, bottom = 10, left = 10 }

hl = {
  config = function(value) table.insert(configs, value) end,
  workspace_rule = function(rule) table.insert(rules, rule) end,
  on = function(event, callback) handlers[event] = callback end,
  get_config = function(key)
    if key == "general.gaps_out" then return gaps end
    return nil
  end,
  get_monitors = function() return monitors end,
  get_workspaces = function() return workspaces end,
  get_workspace_windows = function() return windows end,
  get_active_workspace = function() return active_workspace end,
  get_active_special_workspace = function() return special_workspace end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")

local prelude = os.getenv("OMARCHY_HALF_TILE_PRELUDE") or ""
if prelude ~= "" then
  assert(load(prelude))()
end

require("default.hypr.half-tile")

local function current_for(selector)
  local found
  for _, rule in ipairs(rules) do
    if rule.workspace == selector then
      found = rule
    end
  end
  return found
end

local prelude_fn = _G.omarchy_half_tile_check
if type(prelude_fn) == "function" then
  prelude_fn({
    rules = rules,
    handlers = handlers,
    configs = configs,
    current_for = current_for,
    set_monitors = function(value) monitors = value end,
    set_workspaces = function(value) workspaces = value end,
    set_windows = function(value) windows = value end,
    set_active_workspace = function(value) active_workspace = value end,
    set_special_workspace = function(value) special_workspace = value end,
    set_gaps = function(value) gaps = value end,
  })
end
LUA
}

# No flag file: a single window keeps the full work area.
run_half_tile 'omarchy_half_tile_check = function(ctx)
  assert(#ctx.rules == 0, "disabled half-tile writes no workspace rules")
  assert(o.half_tile_move("left") == false, "move is a no-op while the flag is off")
end' || fail "disabled half-tile leaves a lone window full width"
pass "disabled half-tile leaves a lone window full width"

# The square-aspect flag must not turn half-tile on by itself.
cat >"$home/.local/state/omarchy/toggles/hypr/single-window-aspect-ratio.lua" <<'LUA'
hl.config({ layout = { single_window_aspect_ratio = { 1, 1 } } })
LUA
run_half_tile 'omarchy_half_tile_check = function(ctx)
  assert(#ctx.rules == 0, "square aspect does not write half-tile workspace rules")
  assert(o.half_tile_move("left") == false, "square aspect does not steal Super+Shift+Left")
end' || fail "square aspect stays independent of half-tile"
pass "square aspect stays independent of half-tile"
rm -f "$home/.local/state/omarchy/toggles/hypr/single-window-aspect-ratio.lua"

# Half-tile is its own opt-in flag.
cat >"$home/.local/state/omarchy/toggles/hypr/single-window-half-tile.lua" <<'LUA'
-- marker
LUA

run_half_tile 'omarchy_half_tile_check = function(ctx)
  local monitor = {
    name = "DP-1",
    width = 2560,
    scale = 1,
    reserved = { top = 26, bottom = 0, left = 0, right = 0 },
  }
  ctx.set_monitors({ monitor })
  ctx.set_workspaces({
    { id = 1, special = false, monitor = monitor },
  })
  ctx.handlers["monitor.layout_changed"]()

  local generic = ctx.current_for("w[tv1]s[false] m[DP-1]")
  local specific = ctx.current_for("r[1-1] w[tv1]s[false] m[DP-1]")
  assert(generic, "enabled half-tile rules every single-window workspace")
  assert(specific, "and the workspace that already exists")
  assert(generic.gaps_out.left == 10 and generic.gaps_out.right == 1280,
    "a lone window starts on the left half")
  assert(specific.gaps_out.right == 1280, "workspace 1 follows the default left half")

  local scaled = {
    name = "DP-2",
    width = 5120,
    scale = 2,
    reserved = { top = 26, bottom = 0, left = 0, right = 0 },
  }
  ctx.set_monitors({ scaled })
  ctx.set_workspaces({
    { id = 1, special = false, monitor = scaled },
  })
  ctx.handlers["monitor.layout_changed"]()
  local scaled_rule = ctx.current_for("w[tv1]s[false] m[DP-2]")
  assert(scaled_rule.gaps_out.right == 1280, "scale comes out before the half is measured")

  ctx.set_windows({ { mapped = true, floating = false } })
  ctx.set_active_workspace({ id = 1, special = false, monitor = scaled })
  assert(o.half_tile_move("right") == true, "a lone tiled window can move to the right half")
  local moved = ctx.current_for("r[1-1] w[tv1]s[false] m[DP-2]")
  assert(moved.gaps_out.left == 1280 and moved.gaps_out.right == 10,
    "Super+Shift+Right parks the window on the right half")

  ctx.set_windows({
    { mapped = true, floating = false },
    { mapped = true, floating = false },
  })
  assert(o.half_tile_move("left") == false, "two tiled windows still swap")

  ctx.set_windows({ { mapped = true, floating = false } })
  ctx.set_special_workspace({ id = -98, special = true })
  assert(o.half_tile_move("left") == false, "the scratchpad is not half-tiled")

  local squared = false
  for _, config in ipairs(ctx.configs) do
    if config.layout and config.layout.single_window_aspect_ratio then
      local ratio = config.layout.single_window_aspect_ratio
      if ratio[1] == 0 and ratio[2] == 0 then
        squared = true
      end
    end
  end
  assert(squared, "half-tile disables the centered square so the two cannot nest")
end' || fail "enabled half-tile parks a lone window on the left or right half"
pass "enabled half-tile parks a lone window on the left or right half"

# An expired monitor handle is what a layout change looks like mid-flight.
run_half_tile 'omarchy_half_tile_check = function(ctx)
  local monitor = {
    name = "DP-1",
    width = 2560,
    scale = 1,
    reserved = { top = 0, bottom = 0, left = 0, right = 0 },
  }
  ctx.set_monitors({ monitor })
  ctx.set_workspaces({ { id = 1, special = false, monitor = monitor } })
  ctx.handlers["monitor.layout_changed"]()
  local before = #ctx.rules

  ctx.set_monitors({ setmetatable({}, { __index = function() return nil end }) })
  ctx.handlers["monitor.layout_changed"]()
  assert(#ctx.rules == before, "an expired monitor handle is not read to pieces")
end' || fail "half-tile ignores expired monitor handles"
pass "half-tile ignores expired monitor handles"

stub="$home/bin"
mkdir -p "$stub"
cat >"$stub/hyprctl" <<'EOF'
#!/bin/bash
:
EOF
cat >"$stub/omarchy-notification-send" <<'EOF'
#!/bin/bash
:
EOF
chmod +x "$stub/hyprctl" "$stub/omarchy-notification-send"

flag_dir="$home/.local/state/omarchy/toggles/hypr"
run_toggle() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub:$ROOT/bin:$PATH" "$@" >/dev/null
}

rm -f "$flag_dir"/*.lua
cp "$ROOT/default/hypr/toggles/single-window-aspect-ratio.lua" "$flag_dir/"
run_toggle "$ROOT/bin/omarchy-hyprland-window-single-half-tile-toggle"
[[ -f $flag_dir/single-window-half-tile.lua ]] || fail "enabling half-tile writes its flag"
[[ ! -e $flag_dir/single-window-aspect-ratio.lua ]] || fail "enabling half-tile drops square aspect"
pass "enabling half-tile turns square aspect off"

run_toggle "$ROOT/bin/omarchy-hyprland-window-single-square-aspect-toggle"
[[ -f $flag_dir/single-window-aspect-ratio.lua ]] || fail "enabling square aspect writes its flag"
[[ ! -e $flag_dir/single-window-half-tile.lua ]] || fail "enabling square aspect drops half-tile"
pass "enabling square aspect turns half-tile off"
