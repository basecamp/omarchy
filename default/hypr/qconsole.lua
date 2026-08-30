-- The scratchpad, presented as a Quake console: a dimmed overlay that drops
-- down over whatever workspace you are on. Its bindings live in
-- bindings/tiling.lua, and its slide is animated below.

-- How much of the usable screen the console covers, measured from the top.
local share = 0.5
local min_size = 64

local SCRATCHPAD = "special:scratchpad"

-- Seed the console with the default agent the first time it opens, rather than
-- at boot, so nothing is running until it is wanted. The exec rule has to pin
-- the workspace itself: Hyprland only tags a spawn with the workspace it came
-- from while misc.initial_workspace_tracking is on, and looknfeel turns it off.
-- Omarchy ships without a default agent, and omarchy-agent exits without
-- opening anything when none is set, so until one is picked this just opens an
-- empty console.
local seed = "[workspace special:scratchpad silent] omarchy-agent"

-- Dimming only applies while a special workspace is open, so the console gets
-- its separation from the workspace underneath without costing anything the
-- rest of the time.
hl.config({
  decoration = {
    dim_special = 0.6,
  },
})

-- Refitting replaces the rule in place rather than stacking a new one, but it
-- still schedules a monitor and window state refresh, and monitor.focused fires
-- on every hop between screens. Most of those hops do not change the gaps, so
-- only write the rule when it actually moves.
local covering = nil

local function same_gaps(a, b)
  return a
    and b
    and a.top == b.top
    and a.right == b.right
    and a.bottom == b.bottom
    and a.left == b.left
end

local function cover(gaps_out)
  if type(gaps_out) == "number" then
    gaps_out = { top = 0, right = 0, bottom = gaps_out, left = 0 }
  end

  if same_gaps(covering, gaps_out) then
    return false
  end
  covering = gaps_out

  hl.workspace_rule({
    workspace = SCRATCHPAD,
    gaps_in = 0,
    gaps_out = gaps_out,

    -- Nothing to highlight in a console that is only ever focused when it is
    -- open, and the active border reads as a stray frame around a panel that
    -- is already set apart by the dimming behind it.
    no_border = true,

    on_created_empty = seed,
  })

  return true
end

local function reserved_edges(monitor)
  local reserved = monitor.reserved
  if type(reserved) ~= "table" then
    return { top = 0, right = 0, bottom = 0, left = 0 }
  end

  return {
    top = reserved.top or 0,
    right = reserved.right or 0,
    bottom = reserved.bottom or 0,
    left = reserved.left or 0,
  }
end

-- A positive omarchy_qconsole_ratio (set in hyprland.lua before defaults load)
-- centers the console in a tiling box that many times wider than it is tall.
-- Values below 1 clamp to a square. Unset keeps the full-width drop-down.
local function box_ratio()
  local ratio = _G.omarchy_qconsole_ratio
  if type(ratio) == "number" and ratio > 0 then
    return math.max(1, ratio)
  end
  return nil
end

local function is_scratchpad(ws)
  return ws and (ws.name == SCRATCHPAD or ws.name == "scratchpad")
end

-- Sizing the console with a window rule would freeze it at whatever the screen
-- measured when it first opened, because Hyprland resolves those expressions
-- once, as the window maps. Rescaling the monitor afterwards would leave a
-- console that is no longer half of anything. Gaps are re-applied by the layout
-- instead, so the console is sized by the leftover area and that area is
-- recomputed whenever the monitor it is opening on changes.
local function fit(monitor)
  monitor = monitor or hl.get_active_monitor()

  -- A monitor handle whose output has gone away answers nil to every field, and
  -- layout changes are exactly when that happens, so this also covers reading
  -- height and reserved below.
  if not monitor or not monitor.scale or monitor.scale <= 0 then
    return false
  end

  -- Monitor dimensions are in physical pixels; gaps are logical, so the scale
  -- has to come out before the reserved area (already logical) comes off.
  local reserved = reserved_edges(monitor)
  local usable_h = monitor.height / monitor.scale - reserved.top - reserved.bottom
  local usable_w = nil
  if monitor.width then
    usable_w = monitor.width / monitor.scale - reserved.left - reserved.right
  end

  local ratio = box_ratio()
  local h = math.max(min_size, math.floor(usable_h * share))
  local side = 0
  local bottom = math.max(0, math.floor(usable_h - h))

  if ratio and usable_w then
    local w = math.floor(h * ratio)
    if w > usable_w then
      w = math.floor(usable_w)
    end
    side = math.max(0, math.floor((usable_w - w) / 2))
    if usable_w - (side * 2) < min_size then
      side = math.max(0, math.floor((usable_w - min_size) / 2))
    end
  end

  if usable_h - bottom < min_size then
    bottom = math.max(0, math.floor(usable_h - min_size))
  end

  return cover({ top = 0, right = side, bottom = bottom, left = side })
end

local function apply_now()
  if hl.exec_scheduled_prop_refresh_immediately then
    hl.exec_scheduled_prop_refresh_immediately()
  end
end

local function scratchpad_on_other_monitor(mon)
  if not hl.get_workspace or not mon then
    return false
  end

  local ws = hl.get_workspace(SCRATCHPAD)
  if not is_scratchpad(ws) or not ws.visible or not ws.monitor or not ws.monitor.name or not mon.name then
    return false
  end

  return ws.monitor.name ~= mon.name
end

-- Until a monitor can be read, cover the whole work area rather than leaving
-- the console unruled, so it is never seeded without its placement.
cover({ top = 0, right = 0, bottom = 0, left = 0 })
fit()

hl.on("monitor.layout_changed", function()
  local ws = hl.get_workspace and hl.get_workspace(SCRATCHPAD)
  if is_scratchpad(ws) and ws.visible and ws.monitor then
    fit(ws.monitor)
  else
    fit()
  end
end)

-- follow_mouse hops fire this; do not rewrite an open console to a different
-- output's gaps (that is what zeroed the window on the 1080p screen).
hl.on("monitor.focused", function(mon)
  if scratchpad_on_other_monitor(mon) then
    return
  end
  fit(mon)
end)

-- Special workspaces toggle on the monitor they open on, not whichever output
-- last happened to be focused when the rule was written.
hl.on("workspace.special_active", function(ws, mon)
  if not is_scratchpad(ws) then
    return
  end
  if fit(mon) then
    apply_now()
  end
end)

hl.on("workspace.move_to_monitor", function(ws, mon)
  if not is_scratchpad(ws) then
    return
  end
  if fit(mon) then
    apply_now()
  end
end)

-- The direction names the edge the offset is measured from, not where the
-- workspace goes: "slide top" drops it down into view, and "slide bottom"
-- retracts it back up the way a Quake console does.
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 3, bezier = "easeOutQuint", style = "slide top" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2, bezier = "easeInOutCubic", style = "slide bottom" })
