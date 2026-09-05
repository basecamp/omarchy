-- Send with explicit mods to the focused surface by omitting the window target,
-- so universal clipboard shortcuts reach both normal windows and focused
-- layer-shell surfaces such as Omarchy panels. A virtual keyboard (wtype) won't
-- do: the physically held SUPER merges into the injected chord at the seat.
-- The down/up split works around Hyprland send_shortcut sometimes leaving
-- synthetic key state stuck/repeating.
-- https://github.com/hyprwm/Hyprland/discussions/14099
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

-- Name the letters by keycode, not by keysym. Hyprland resolves a keysym name
-- against the *active* keymap, so "C" is simply absent while a non-Latin layout
-- (ru, uk, bg, el, ...) is selected: send_key_state then aborts with
-- "key not found" and the shortcut only pops a Hyprland error notification.
-- A keycode is layout-independent and is exactly what a physical press emits,
-- so clients keep applying their usual Latin-fallback accelerator matching.
-- Insert stays a name; it is present in every layout.
local KEY_C = "code:54" -- AB03
local KEY_V = "code:55" -- AB04
local KEY_X = "code:53" -- AB02

o.bind("SUPER + C", "Universal copy", universal_clipboard_shortcut("CTRL", KEY_C, "CTRL", "Insert"))
o.bind("SUPER + V", "Universal paste", universal_clipboard_shortcut("CTRL", KEY_V, "SHIFT", "Insert"))
o.bind("SUPER + X", "Universal cut", send_shortcut_once("CTRL", KEY_X))
o.bind("SUPER + CTRL + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")
