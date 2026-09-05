local function universal_clipboard_shortcut(default_mods, default_key, terminal_mods, terminal_key)
  return function()
    if o.active_window_has_tag("terminal") then
      o.send_shortcut_once(terminal_mods, terminal_key)()
    else
      o.send_shortcut_once(default_mods, default_key)()
    end
  end
end

o.bind("SUPER + C", "Universal copy", universal_clipboard_shortcut("CTRL", "C", "CTRL", "Insert"))
o.bind("SUPER + V", "Universal paste", universal_clipboard_shortcut("CTRL", "V", "SHIFT", "Insert"))
o.bind("SUPER + X", "Universal cut", o.send_shortcut_once("CTRL", "X"))
o.bind("SUPER + CTRL + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")
