-- Work around Hyprland send_shortcut sometimes leaving synthetic key state stuck/repeating.
-- https://github.com/hyprwm/Hyprland/discussions/14099
local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down", window = "activewindow" }))

    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up", window = "activewindow" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

hl.bind("SUPER + C", send_shortcut_once("CTRL", "Insert"), { description = "Universal copy" })
hl.bind("SUPER + V", send_shortcut_once("SHIFT", "Insert"), { description = "Universal paste" })
hl.bind("SUPER + X", send_shortcut_once("CTRL", "X"), { description = "Universal cut" })
hl.bind("SUPER + CTRL + V", hl.dsp.exec_cmd("omarchy-launch-walker -m clipboard"), { description = "Clipboard manager" })
