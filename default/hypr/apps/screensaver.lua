-- Fullscreen screensaver.
o.window("org.omarchy.screensaver", { fullscreen = true })
o.window("org.omarchy.screensaver", { float = true })
o.window("org.omarchy.screensaver", { animation = "slide" })

-- Hyprland draws pinned windows in a pass of their own, after the workspace,
-- so a pinned pop-out or picture-in-picture window stays on top of the
-- fullscreen screensaver. No window rule changes that order. Drop the pin
-- while the screensaver is up and put it back when it goes away.
--
-- The pin has to go before the screensaver takes fullscreen, because Hyprland
-- skips pinned windows when it hides the windows under a new fullscreen
-- window. That is why the first pass runs on window.open_early. The second
-- pass on window.open lowers whatever the first pass missed, which clears the
-- same "allowed over fullscreen" flag.

local SCREENSAVER_CLASS = "org.omarchy.screensaver"

-- Addresses of the open screensaver windows. One opens on each monitor.
local screensavers = {}

-- Addresses of the windows unpinned here, from the bottom of the stack up.
local unpinned = {}
local unpinned_set = {}

local function window_at(address)
  if not address then
    return nil
  end

  return hl.get_window("address:" .. address)
end

local function set_pin(window, action)
  hl.dispatch(hl.dsp.window.pin({ action = action, window = window }))
end

local function set_zorder(window, mode)
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = mode, window = window }))
end

-- Count the open screensaver windows and forget the ones that are gone.
local function screensaver_count()
  local total = 0

  for address in pairs(screensavers) do
    local window = window_at(address)
    if window and window.mapped then
      total = total + 1
    else
      screensavers[address] = nil
    end
  end

  return total
end

local function unpin(window)
  local address = window.address
  if not address or unpinned_set[address] then
    return
  end

  unpinned_set[address] = true
  table.insert(unpinned, address)
  set_pin(window, "off")
end

local function unpin_pinned_windows()
  for _, window in ipairs(hl.get_windows()) do
    if window.pinned and window.class ~= SCREENSAVER_CLASS then
      unpin(window)
    end
  end
end

-- Push anything the compositor still ranks above the screensaver below it.
local function lower_unpinned()
  for _, address in ipairs(unpinned) do
    local window = window_at(address)
    if window and window.allowed_over_fullscreen then
      set_zorder(window, "bottom")
    end
  end
end

local function restore_pins()
  -- The list runs bottom to top, so each raise lands the next window above the
  -- previous one and the old stack order comes back.
  for _, address in ipairs(unpinned) do
    local window = window_at(address)
    if window then
      set_zorder(window, "top")
      set_pin(window, "on")
    end
  end

  unpinned = {}
  unpinned_set = {}
end

local function on_screensaver_open(window)
  screensavers[window.address] = true
  unpin_pinned_windows()
end

hl.on("window.open_early", function(window)
  if window.class == SCREENSAVER_CLASS then
    on_screensaver_open(window)
  end
end)

hl.on("window.open", function(window)
  if window.class == SCREENSAVER_CLASS then
    on_screensaver_open(window)
    lower_unpinned()
  elseif next(screensavers) and window.pinned then
    -- A pinned window opened while the screensaver was already up.
    unpin(window)
    lower_unpinned()
  end
end)

-- The window is still mapped on window.close, so the count reaches zero only
-- on window.destroy. Both events keep the address list correct.
local function on_window_gone(window)
  local address = window.address
  if address then
    screensavers[address] = nil
  end

  if #unpinned == 0 then
    return
  end

  if screensaver_count() == 0 then
    restore_pins()
  end
end

hl.on("window.close", on_window_gone)
hl.on("window.destroy", on_window_gone)
