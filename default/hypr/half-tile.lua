-- When the single-window-half-tile flag is on, a lone tiled window occupies
-- the left or right half of the screen. Super+Shift+Left/Right parks it on that
-- half, and still swaps when there is a real neighbor.

local paths = require("default.hypr.paths")

o = o or {}

local flag = paths.state_home .. "/omarchy/toggles/hypr/single-window-half-tile.lua"
local sides_path = paths.state_home .. "/omarchy/half-tile-sides"
local sides = {}
local applied = {}

local function flag_on()
  local file = io.open(flag, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function load_sides()
  sides = {}
  local file = io.open(sides_path, "r")
  if not file then
    return
  end
  for line in file:lines() do
    local id, side = line:match("^([^=]+)=(left)$")
    if not id then
      id, side = line:match("^([^=]+)=(right)$")
    end
    if id then
      sides[id] = side
    end
  end
  file:close()
end

local function save_sides()
  local file = io.open(sides_path, "w")
  if not file then
    return
  end
  for id, side in pairs(sides) do
    file:write(id .. "=" .. side .. "\n")
  end
  file:close()
end

local function gaps_out()
  local g = hl.get_config("general.gaps_out")
  if type(g) ~= "table" then
    return { top = 10, right = 10, bottom = 10, left = 10 }
  end
  return {
    top = g.top or 10,
    right = g.right or 10,
    bottom = g.bottom or 10,
    left = g.left or 10,
  }
end

local function usable_width(monitor)
  if not monitor or not monitor.scale or monitor.scale <= 0 then
    return nil
  end
  local reserved = monitor.reserved or {}
  return monitor.width / monitor.scale - (reserved.left or 0) - (reserved.right or 0)
end

local function half_gaps(monitor, side)
  local g = gaps_out()
  local usable = usable_width(monitor)
  if not usable then
    return nil
  end

  local extra = math.max(g.left, math.floor(usable / 2))
  if side == "right" then
    return { top = g.top, right = g.right, bottom = g.bottom, left = extra }
  end
  return { top = g.top, right = extra, bottom = g.bottom, left = g.left }
end

local function rule(selector, gaps)
  local key = string.format(
    "%s:%s:%s:%s:%s",
    selector,
    tostring(gaps.top),
    tostring(gaps.right),
    tostring(gaps.bottom),
    tostring(gaps.left)
  )
  if applied[selector] == key then
    return
  end
  applied[selector] = key
  hl.workspace_rule({ workspace = selector, gaps_out = gaps })
end

local function selector_for(id, monitor)
  if id then
    return string.format("r[%s-%s] w[tv1]s[false] m[%s]", id, id, monitor.name)
  end
  return string.format("w[tv1]s[false] m[%s]", monitor.name)
end

local function apply()
  if not flag_on() then
    return
  end
  if type(hl.get_monitors) ~= "function" or type(hl.workspace_rule) ~= "function" then
    return
  end

  if type(hl.config) == "function" then
    hl.config({ layout = { single_window_aspect_ratio = { 0, 0 } } })
  end

  local monitors = hl.get_monitors() or {}
  for _, monitor in ipairs(monitors) do
    if monitor.name then
      local gaps = half_gaps(monitor, "left")
      if gaps then
        rule(selector_for(nil, monitor), gaps)
      end
    end
  end

  for _, ws in ipairs(hl.get_workspaces() or {}) do
    if not ws.special and ws.id and ws.id > 0 then
      local monitor = ws.monitor
      if monitor and monitor.name then
        local side = sides[tostring(ws.id)] or "left"
        local gaps = half_gaps(monitor, side)
        if gaps then
          rule(selector_for(tostring(ws.id), monitor), gaps)
        end
      end
    end
  end
end

local function tiled_count(ws)
  local count = 0
  for _, window in ipairs(hl.get_workspace_windows(ws) or {}) do
    if window.mapped and not window.floating then
      count = count + 1
    end
  end
  return count
end

function o.half_tile_move(side)
  if side ~= "left" and side ~= "right" then
    return false
  end
  if not flag_on() then
    return false
  end
  if type(hl.get_active_special_workspace) == "function" and hl.get_active_special_workspace() then
    return false
  end
  if type(hl.get_active_workspace) ~= "function" then
    return false
  end

  local ws = hl.get_active_workspace()
  if not ws or ws.special or tiled_count(ws) ~= 1 then
    return false
  end

  sides[tostring(ws.id)] = side
  save_sides()
  apply()
  return true
end

load_sides()
apply()

if type(hl.on) == "function" then
  hl.on("monitor.layout_changed", apply)
  hl.on("window.open", apply)
  pcall(function()
    hl.on("window.close", apply)
  end)
  pcall(function()
    hl.on("workspace.move_to_monitor", apply)
  end)
end
