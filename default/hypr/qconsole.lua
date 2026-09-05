-- The scratchpad, presented as a Quake console: a dimmed overlay that drops
-- down over whatever workspace you are on. Its bindings live in
-- bindings/tiling.lua, and its slide is animated below.

-- How much of the usable screen the console covers, measured from the top.
local share = 0.5

-- A console holding a single window is boxed into a centered panel this many
-- times wider than it is tall, rather than stretched the width of the screen.
-- A second app on the scratchpad gets the full width back: two windows splitting
-- a half-width column is worse than the band this replaced.
local box = 2

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

-- The panel is always flush with the top and always centered, so two numbers
-- describe it: the gap down each side and the gap underneath.
--
-- Refitting replaces the rule in place rather than stacking a new one, but it
-- still schedules a monitor and window state refresh, and monitor.focused fires
-- on every hop between screens. Most of those hops do not change the gaps, so
-- only write the rule when it actually moves.
local beside, below = nil, nil

local function cover(side, bottom)
  if beside == side and below == bottom then
    return false
  end
  beside, below = side, bottom

  hl.workspace_rule({
    workspace = SCRATCHPAD,
    gaps_in = 0,
    gaps_out = { top = 0, right = side, bottom = bottom, left = side },

    -- Nothing to highlight in a console that is only ever focused when it is
    -- open, and the active border reads as a stray frame around a panel that
    -- is already set apart by the dimming behind it.
    no_border = true,

    on_created_empty = seed,
  })

  return true
end

-- One window reads as a console and gets the panel. A second app has turned the
-- scratchpad into a workspace, and a workspace wants the whole width.
local function alone()
  local ws = hl.get_workspace(SCRATCHPAD)
  return not ws or ws.windows <= 1
end

-- Sizing the console with a window rule would freeze it at whatever the screen
-- measured when it first opened, because Hyprland resolves those expressions
-- once, as the window maps. Rescaling the monitor afterwards would leave a
-- console that is no longer half of anything. Gaps are re-applied by the layout
-- instead, so the console is sized by the area left around it, and that area is
-- recomputed whenever the monitor it opens on changes.
local function fit(monitor)
  -- A monitor handle whose output has gone away answers nil to every field, and
  -- layout changes are exactly when that happens, so this also covers reading
  -- width, height and reserved below.
  if not monitor or not monitor.scale or monitor.scale <= 0 then
    return false
  end

  -- Width and height are the panel's own pixels, so a monitor turned on its
  -- side still reports them the way the panel is built. The odd transforms are
  -- the quarter turns, and those are the ones that swap the work area.
  local width, height = monitor.width, monitor.height
  if monitor.transform % 2 == 1 then
    width, height = height, width
  end

  -- Monitor dimensions are in physical pixels; gaps are logical, so the scale
  -- has to come out before the reserved area (already logical) comes off.
  local reserved = monitor.reserved
  height = height / monitor.scale - reserved.top - reserved.bottom
  width = width / monitor.scale - reserved.left - reserved.right

  local tall = math.floor(height * share)
  local wide = width
  if alone() then
    wide = math.min(width, tall * box)
  end

  return cover(math.floor((width - wide) / 2), math.floor(height - tall))
end

-- The console keeps the geometry of the output it is open on: a follow_mouse hop
-- onto another screen must not resize a console that is already showing. While
-- it is hidden there is nothing to size but the output that will show it next.
local function console_monitor()
  local ws = hl.get_workspace(SCRATCHPAD)
  local mon = ws and ws.visible and ws.monitor

  if mon and mon.scale and mon.scale > 0 then
    return mon
  end

  return hl.get_active_monitor()
end

local function refit(monitor)
  if fit(monitor or console_monitor()) then
    -- Land the new gaps in this pass rather than a frame later, so the console
    -- does not visibly resize itself once it has already dropped down.
    hl.exec_scheduled_prop_refresh_immediately()
  end
end

-- Until a monitor can be read, cover the whole work area rather than leaving
-- the console unruled, so it is never seeded without its placement. A reload
-- runs this again with the console already on screen, so it starts from the
-- output the console is on rather than whichever one the pointer is over.
cover(0, 0)
fit(console_monitor())

hl.on("monitor.layout_changed", function()
  refit()
end)

hl.on("monitor.focused", function()
  refit()
end)

-- Special workspaces open on the monitor they are toggled on, not on whichever
-- output last happened to be focused when the rule was written, so these two
-- take the monitor they are handed rather than looking one up.
hl.on("workspace.special_active", function(ws, mon)
  if ws and ws.name == SCRATCHPAD then
    refit(mon)
  end
end)

hl.on("workspace.move_to_monitor", function(ws, mon)
  if ws and ws.name == SCRATCHPAD then
    refit(mon)
  end
end)

-- The panel is only centered while the console holds one window, so the count
-- has to be rechecked as apps come and go. These are the two events that run
-- after the workspace's count has already moved: window.close and
-- window.move_to_workspace still count the window on its way out, and refitting
-- from those would read one too many and leave the console full width.
--
-- Only while it is on screen, though. A hidden console is refitted on its way in
-- by workspace.special_active, and every window opened anywhere on the desktop
-- would otherwise rewrite the rule.
local function recount()
  local ws = hl.get_workspace(SCRATCHPAD)
  if ws and ws.visible then
    refit()
  end
end

hl.on("window.open", recount)
hl.on("window.destroy", recount)

-- The direction names the edge the offset is measured from, not where the
-- workspace goes: "slide top" drops it down into view, and "slide bottom"
-- retracts it back up the way a Quake console does.
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 3, bezier = "easeOutQuint", style = "slide top" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2, bezier = "easeInOutCubic", style = "slide bottom" })
