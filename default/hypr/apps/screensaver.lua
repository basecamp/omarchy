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

-- Every unpinned window carries this tag, and the tag is the only record of
-- the work. A config reload replaces the Lua state, so state in a local table
-- would strand the windows unpinned. A tag from a dispatcher stays on the
-- window: Hyprland only drops the dynamic tags that window rules apply.
local UNPINNED_TAG = "omarchy-screensaver-unpinned"

local function set_pin(window, action)
  hl.dispatch(hl.dsp.window.pin({ action = action, window = window }))
end

local function set_tag(window, tag)
  hl.dispatch(hl.dsp.window.tag({ tag = tag, window = window }))
end

local function set_zorder(window, mode)
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = mode, window = window }))
end

local function screensaver_windows()
  return hl.get_windows({ class = SCREENSAVER_CLASS })
end

-- hl.get_windows returns the stack from the bottom up, which is the order the
-- windows need for the raise in restore_pins.
local function unpinned_windows()
  return hl.get_windows({ tag = UNPINNED_TAG })
end

local function unpin(window)
  set_tag(window, "+" .. UNPINNED_TAG)
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
  for _, window in ipairs(unpinned_windows()) do
    if window.allowed_over_fullscreen then
      set_zorder(window, "bottom")
    end
  end
end

-- Each raise lands the next window above the previous one, so the windows come
-- back in the order they had.
local function restore_pins()
  for _, window in ipairs(unpinned_windows()) do
    set_zorder(window, "top")
    set_pin(window, "on")

    -- Hyprland refuses the pin while a window is fullscreen. Keep the tag on
    -- such a window so that a later pass picks it up again.
    if window.pinned then
      set_tag(window, "-" .. UNPINNED_TAG)
    end
  end
end

local function restore_pins_if_screensaver_gone()
  if #unpinned_windows() == 0 then
    return
  end

  if #screensaver_windows() == 0 then
    restore_pins()
  end
end

hl.on("window.open_early", function(window)
  if window.class == SCREENSAVER_CLASS then
    unpin_pinned_windows()
  end
end)

hl.on("window.open", function(window)
  if window.class == SCREENSAVER_CLASS then
    unpin_pinned_windows()
    lower_unpinned()
  elseif window.pinned and #screensaver_windows() > 0 then
    unpin(window)
    lower_unpinned()
  end
end)

-- A window can also gain the pin later, from omarchy-hyprland-window-pop or
-- from a keybind. The unpin here makes the event fire again with the pin off,
-- and that second pass stops at the check below.
hl.on("window.pin", function(window)
  if window.pinned and window.class ~= SCREENSAVER_CLASS and #screensaver_windows() > 0 then
    unpin(window)
    lower_unpinned()
  end
end)

-- The window is still mapped on window.close, so the count reaches zero only
-- on window.destroy. Both events keep the check honest.
hl.on("window.close", restore_pins_if_screensaver_gone)
hl.on("window.destroy", restore_pins_if_screensaver_gone)

-- A reload during the screensaver leaves this file with no memory of the work.
-- The tags carry it, so pick the windows back up here.
hl.on("config.reloaded", restore_pins_if_screensaver_gone)

-- Retry for a window that was fullscreen when the screensaver went away.
hl.on("window.fullscreen", restore_pins_if_screensaver_gone)
