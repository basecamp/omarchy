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

local terminal_classes = {
  alacritty = true,
  ["com.mitchellh.ghostty"] = true,
  foot = true,
  kitty = true,
  wezterm = true,
}

-- Omarchy launches its own TUIs through xdg-terminal-exec with app-ids such as
-- org.omarchy.btop, org.omarchy.terminal and TUI.float, so the window class
-- never matches the list above even though the client is a terminal. Fall back
-- to the client process, which names the terminal regardless of the app-id.
local terminal_processes = {
  alacritty = true,
  foot = true,
  footclient = true,
  ghostty = true,
  kitty = true,
  wezterm = true,
  ["wezterm-gui"] = true,
}

local function client_process_name(pid)
  if not pid or pid <= 0 then
    return nil
  end

  local file = io.open("/proc/" .. pid .. "/comm", "r")
  if not file then
    return nil
  end

  local name = file:read("*l")
  file:close()

  return name
end

local function active_window_is_terminal()
  local window = hl.get_active_window()
  if not window then
    return false
  end

  if window.class and terminal_classes[window.class:lower()] == true then
    return true
  end

  local process = client_process_name(window.pid)

  return process ~= nil and terminal_processes[process:lower()] == true
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
