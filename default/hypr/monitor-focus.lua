-- Hyprland clears focus when the sole monitor drops onto the headless FALLBACK,
-- and doesn't put it back when the real one returns, so the session takes no
-- keyboard input until you switch workspace by hand. Upstream considers this
-- intended, see hyprwm/Hyprland discussion #15554.

local fallback_monitor = "FALLBACK"
local restore_delay_ms = 500

local went_headless = false
local restore_generation = 0
-- Ids, not objects. The objects don't survive the migration.
local saved_workspace_id = nil
local saved_window_address = nil

-- A newer monitor event makes a pending restore stale.
local function invalidate_pending()
  restore_generation = restore_generation + 1
end

local function forget_saved()
  saved_workspace_id = nil
  saved_window_address = nil
end

local function focused_window()
  for _, window in ipairs(hl.get_windows()) do
    if window.active then
      return window
    end
  end
end

-- Lowest focus_history_id is the most recently focused window.
local function most_recent_window(workspace_id)
  local best = nil
  for _, window in ipairs(hl.get_workspace_windows(workspace_id) or {}) do
    if not best or window.focus_history_id < best.focus_history_id then
      best = window
    end
  end
  return best
end

local function current_workspace_id()
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.focused then
      return monitor.active_workspace and monitor.active_workspace.id
    end
  end
end

local function other_workspace(target_id)
  for _, workspace in ipairs(hl.get_workspaces()) do
    if workspace.id ~= target_id and not tostring(workspace.name):match("^special:") then
      return workspace
    end
  end
end

local function restore_focus(workspace_id, window_address)
  local workspace = hl.get_workspace(workspace_id)
  if not workspace then
    return
  end

  -- Refocusing the workspace Hyprland already records as focused is a no-op.
  if current_workspace_id() == workspace_id then
    local via = other_workspace(workspace_id)
    if via then
      hl.dispatch(hl.dsp.focus({ workspace = via }))
    end
  end
  hl.dispatch(hl.dsp.focus({ workspace = workspace }))

  -- The selector needs the address: prefix, a bare address resolves to nil.
  local window = window_address and hl.get_window("address:" .. window_address)
  window = window or most_recent_window(workspace_id)
  if window then
    hl.dispatch(hl.dsp.focus({ window = window }))
  end
end

hl.on("monitor.removed", function(monitor)
  if monitor.name == fallback_monitor then
    return
  end

  invalidate_pending()

  -- Hyprland still reports the pre-lock window as active here.
  local window = focused_window()
  local workspace = window and window.workspace or monitor.active_workspace
  if not workspace then
    forget_saved()
    return
  end

  saved_workspace_id = workspace.id
  saved_window_address = window and window.address or nil
end)

hl.on("monitor.added", function(monitor)
  if monitor.name == fallback_monitor then
    invalidate_pending()
    went_headless = true
    return
  end

  if not went_headless then
    -- An ordinary hotplug, nothing to put back.
    forget_saved()
    return
  end

  went_headless = false
  local workspace_id, window_address = saved_workspace_id, saved_window_address
  forget_saved()

  if not workspace_id then
    return
  end

  -- The monitor needs a moment to settle before focus will stick.
  invalidate_pending()
  local generation = restore_generation

  hl.timer(function()
    if generation == restore_generation then
      restore_focus(workspace_id, window_address)
    end
  end, { timeout = restore_delay_ms, type = "oneshot" })
end)
