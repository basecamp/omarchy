-- Send with explicit mods to the focused surface by omitting the window target,
-- so universal clipboard shortcuts reach both normal windows and focused
-- layer-shell surfaces such as Omarchy panels. A virtual keyboard (wtype) won't
-- do: the physically held SUPER merges into the injected chord at the seat.
-- The down/up split works around Hyprland send_shortcut sometimes leaving
-- synthetic key state stuck/repeating.
-- https://github.com/hyprwm/Hyprland/discussions/14099
--
-- Letter keysyms in send_key_state are resolved against the active layout, so
-- SUPER+C/V/X fail with "key not found" while a non-Latin layout is active.
-- Use Hyprland's `code:` key identifiers with evdev scancodes so these
-- shortcuts work regardless of the active keyboard layout.
local KEY_X      = "code:53"   -- KEY_X      (linux/input-event-codes.h)
local KEY_C      = "code:54"   -- KEY_C
local KEY_V      = "code:55"   -- KEY_V
local KEY_INSERT = "code:118"  -- KEY_INSERT

local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))

    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

-- Lean on the terminal tag from default/hypr/apps/terminals.lua so there's one
-- definition of what counts as a terminal. Dynamic tags carry a trailing "*".
local function active_window_is_terminal()
  local window = hl.get_active_window()
  if not window then
    return false
  end

  for _, tag in ipairs(window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end

  return false
end

local function universal_clipboard_shortcut(default_mods, default_key, terminal_mods, terminal_key)
  return function()
    if active_window_is_terminal() then
      send_shortcut_once(terminal_mods, terminal_key)()
    else
      send_shortcut_once(default_mods, default_key)()
    end
  end
end

o.bind("SUPER + C", "Universal copy", universal_clipboard_shortcut("CTRL", KEY_C, "CTRL", KEY_INSERT))
o.bind("SUPER + V", "Universal paste", universal_clipboard_shortcut("CTRL", KEY_V, "SHIFT", KEY_INSERT))
o.bind("SUPER + X", "Universal cut", send_shortcut_once("CTRL", KEY_X))
o.bind("SUPER + CTRL + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")
