-- Workspace modes for omarchy-hyprland-workspace-layout-toggle.
--
-- Hyprland has dwindle and scrolling as tiled layouts, but nothing that floats a
-- whole workspace: it reports a workspace's `tiledLayout` and takes an unknown
-- layout name in silence, falling back to dwindle. So floating is applied to the
-- windows themselves.
--
-- Ending the mode has to tile the windows the mode floated and only those, so
-- each one is tagged. The tag lives on the window: it dies with it, follows it
-- between workspaces, and survives the config reload that a monitor being
-- plugged in performs, none of which a table on this side would do.

require("default.hypr.helpers")

local FLOATED_TAG = "omarchy-mode-floated"

local modes = {}
local watching = false

local function set_floating(window, floating)
  hl.dispatch(hl.dsp.window.float({ action = floating and "on" or "off", window = window }))
end

local function set_claimed(window, claimed)
  hl.dispatch(hl.dsp.window.tag({ tag = (claimed and "+" or "-") .. FLOATED_TAG, window = window }))
end

local function claimed()
  local addresses = {}

  for _, window in ipairs(hl.get_windows({ tag = FLOATED_TAG })) do
    addresses[window.address] = true
  end

  return addresses
end

-- A window already floating on its own account -- an app with a float rule of
-- its own, a dialog, one popped out with SUPER + T -- is left unclaimed, so it
-- is still floating when the mode ends.
local function float_for_mode(window)
  if window.floating then
    return
  end

  set_claimed(window, true)
  set_floating(window, true)
end

-- A pinned window is one the user asked to keep above everything, and tiling it
-- would unpin it as well, so the mode leaves it be.
local function tile_for_mode(window, mine)
  if not mine[window.address] or window.pinned then
    return
  end

  set_claimed(window, false)
  set_floating(window, false)
end

-- Windows arrive by opening and by being carried in, and a window rule only ever
-- fires for the first. One carried back out gives up the floating the mode gave
-- it rather than staying floating somewhere that tiles.
local function watch()
  if watching then
    return
  end

  watching = true

  hl.on("window.open", function(window)
    if modes[tostring(window.workspace.id)] == "floating" then
      float_for_mode(window)
    end
  end)

  hl.on("window.move_to_workspace", function(window, workspace)
    if modes[tostring(workspace.id)] == "floating" then
      float_for_mode(window)
    else
      tile_for_mode(window, claimed())
    end
  end)
end

function o.workspace_mode(spec)
  local workspace = tostring(spec.workspace)
  local floating = spec.mode == "floating"

  watch()

  -- Floating keeps whatever tiled layout the workspace had, so nothing has to be
  -- chosen for it on the way back out.
  if not floating then
    hl.workspace_rule({ workspace = workspace, layout = spec.mode })
  end

  modes[workspace] = spec.mode

  local windows = hl.get_workspace_windows(workspace)

  if floating then
    local claiming = {}

    -- Claim every tiled window before floating any of them: floating one member
    -- of a group floats the rest, and a single pass would then find those
    -- already floating and leave them to be stranded when the mode ends.
    for _, window in ipairs(windows) do
      if not window.floating then
        set_claimed(window, true)
        table.insert(claiming, window)
      end
    end

    for _, window in ipairs(claiming) do
      set_floating(window, true)
    end
  else
    local mine = claimed()

    for _, window in ipairs(windows) do
      tile_for_mode(window, mine)
    end
  end
end
