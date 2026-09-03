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

o.bind("SUPER + C", "Universal copy", universal_clipboard_shortcut("CTRL", "C", "CTRL", "Insert"))
o.bind("SUPER + V", "Universal paste", universal_clipboard_shortcut("CTRL", "V", "SHIFT", "Insert"))
o.bind("SUPER + X", "Universal cut", send_shortcut_once("CTRL", "X"))
o.bind("SUPER + CTRL + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")

-- Of Omarchy's terminal options, only Ghostty has a select-all action to
-- forward to (`ghostty +list-keybinds --default` ships CTRL+SHIFT+A as
-- select_all). foot, kitty, and Alacritty expose no keyboard-triggerable
-- select-all at all, so forwarding CTRL+A there would just fall through to
-- readline's "move to start of line" instead - a no-op is more honest than
-- a shortcut that silently moves the cursor.
local function active_window_is_ghostty()
  local window = hl.get_active_window()
  return window ~= nil and window.class == "com.mitchellh.ghostty"
end

o.bind("SUPER + A", "Universal select all", function()
  if active_window_is_terminal() then
    if active_window_is_ghostty() then
      send_shortcut_once("CTRL SHIFT", "A")()
    end
    return
  end

  send_shortcut_once("CTRL", "A")()
end)
