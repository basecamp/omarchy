-- Send with explicit mods to the focused surface by omitting the window target,
-- so universal clipboard shortcuts reach both normal windows and focused
-- layer-shell surfaces such as Omarchy panels. A virtual keyboard (wtype) won't
-- do: the physically held SUPER merges into the injected chord at the seat.
-- The down/up split works around Hyprland send_shortcut sometimes leaving
-- synthetic key state stuck/repeating. Keep both events in the same callback
-- so Hyprland resolves them against the same keyboard device and layout. Use
-- Insert/Delete chords so letter keys cannot translate through another XKB
-- layout in Electron/Chromium applications.
-- https://github.com/hyprwm/Hyprland/discussions/14099
local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end
end

o.bind("SUPER + C", "Universal copy", send_shortcut_once("CTRL", "Insert"))
o.bind("SUPER + V", "Universal paste", send_shortcut_once("SHIFT", "Insert"))
o.bind("SUPER + X", "Universal cut", send_shortcut_once("SHIFT", "Delete"))
o.bind("SUPER + CTRL + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")
