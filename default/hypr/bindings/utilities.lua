o.bind("SUPER + SPACE", "Launch apps", "omarchy-shell shell toggle omarchy.app-launcher \"{}\"")
o.bind("SUPER + CTRL + E", "Emoji picker", "omarchy-shell shell toggle omarchy.emoji-picker \"{}\"")
o.bind("SUPER + CTRL + C", "Capture menu", "omarchy-shell menu toggle capture")
o.bind("SUPER + CTRL + O", "Toggle menu", "omarchy-shell menu toggle toggle")
o.bind("SUPER + CTRL + H", "Hardware menu", "omarchy-shell menu toggle hardware")
o.bind("SUPER + ALT + SPACE", "Omarchy menu", "omarchy-shell menu toggle root")
o.bind("SUPER + SHIFT + code:201", "Omarchy menu", "omarchy-shell menu toggle root")
o.bind("SUPER + ESCAPE", "System menu", "omarchy-shell menu toggle system")
o.bind("XF86PowerOff", "Power menu", "omarchy-shell menu toggle system", { locked = true })
o.bind("SUPER + K", "Show key bindings", "omarchy-menu-keybindings")
o.bind("SUPER + ALT + K", "Show Tmux key bindings", "omarchy-menu-tmux-keybindings")
o.bind("XF86Calculator", "Calculator", "gnome-calculator")

o.bind_toggle("SUPER + SHIFT + SPACE", "Toggle top bar", "bar")
o.bind("SUPER + SHIFT + CTRL + UP", "Move bar to top", "omarchy-style-bar-position top")
o.bind("SUPER + SHIFT + CTRL + DOWN", "Move bar to bottom", "omarchy-style-bar-position bottom")
o.bind("SUPER + SHIFT + CTRL + LEFT", "Move bar to left", "omarchy-style-bar-position left")
o.bind("SUPER + SHIFT + CTRL + RIGHT", "Move bar to right", "omarchy-style-bar-position right")
o.bind("SUPER + CTRL + SPACE", "Background switcher", "omarchy-shell menu toggle background")
o.bind("SUPER + SHIFT + CTRL + SPACE", "Theme menu", "omarchy-shell menu toggle theme")
o.bind("SUPER + BACKSPACE", "Toggle window transparency", "omarchy-hyprland-window-transparency-toggle")
o.bind("SUPER + SHIFT + BACKSPACE", "Toggle window gaps", "omarchy-hyprland-window-gaps-toggle")
o.bind("SUPER + CTRL + BACKSPACE", "Toggle single-window square aspect", "omarchy-hyprland-window-single-square-aspect-toggle")

-- xkbcommon names the comma keysym "comma"; the upper-case "COMMA" does not match.
o.bind("SUPER + comma", "Dismiss last notification", "omarchy-shell notifications dismissOne")
o.bind("SUPER + SHIFT + comma", "Dismiss all notifications", "omarchy-shell notifications dismissAll")
o.bind_toggle("SUPER + CTRL + comma", "Toggle silencing notifications", "notification-silencing")
o.bind("SUPER + ALT + comma", "Invoke last notification", "omarchy-shell notifications invokeLast")
o.bind("SUPER + SHIFT + ALT + comma", "Open notification history", "omarchy-shell notifications showHistory")

o.bind_toggle("SUPER + CTRL + I", "Toggle locking on idle", "idle")
o.bind_toggle("SUPER + CTRL + N", "Toggle nightlight", "nightlight")
o.bind("SUPER + CTRL + Delete", "Toggle laptop display", "omarchy-hyprland-monitor-internal toggle")
o.bind("SUPER + CTRL + ALT + Delete", "Toggle laptop display mirroring", "omarchy-hyprland-monitor-internal-mirror toggle")
o.bind("switch:on:Lid Switch", nil, "omarchy-hw-external-monitors && omarchy-hyprland-monitor-internal off", { locked = true })
o.bind("switch:off:Lid Switch", nil, "omarchy-hyprland-monitor-internal on", { locked = true })

o.bind("PRINT", "Screenshot", "omarchy-capture-screenshot")
o.bind("ALT + PRINT", "Screenrecording", "omarchy-capture-screenrecording --stop-recording || omarchy-shell menu toggle trigger.capture.screenrecord")
o.bind("SUPER + PRINT", "Color picker", "pkill hyprpicker || hyprpicker -a")
o.bind("SUPER + CTRL + PRINT", "Extract text (OCR) from screenshot", "omarchy-capture-text-extraction")

o.bind("SUPER + CTRL + S", "Share", "omarchy-shell menu toggle share")

o.bind("SUPER + CTRL + PERIOD", "Transcode", "omarchy-transcode")

o.bind("SUPER + CTRL + R", "Set reminder", "omarchy-shell menu toggle reminder-set")
o.bind("SUPER + CTRL + ALT + R", "Show reminders", "omarchy-reminder show")
o.bind("SUPER + SHIFT + CTRL + R", "Clear reminders", "omarchy-reminder clear")

o.bind("SUPER + CTRL + ALT + T", "Show time", "omarchy-notification-time")
o.bind("SUPER + CTRL + ALT + B", "Show battery remaining", "omarchy-notification-battery")
o.bind("SUPER + CTRL + ALT + W", "Show weather", "omarchy-notification-weather")

o.bind("SUPER + CTRL + A", "Audio panel", "omarchy-shell audioPanel toggle")
o.bind("SUPER + CTRL + B", "Bluetooth panel", "omarchy-shell bluetoothPanel toggle")
o.bind("SUPER + CTRL + D", "Display panel", "omarchy-shell monitorPanel toggle")
o.bind("SUPER + CTRL + W", "Network panel", "omarchy-shell networkPanel toggle")
o.bind("SUPER + CTRL + P", "Power panel", "omarchy-shell powerPanel toggle")
o.bind("SUPER + CTRL + T", "Activity", { tui = "btop" })

o.bind("SUPER + CTRL + X", "Toggle dictation", "voxtype record toggle")
o.bind("F9", "Start dictation (push-to-talk)", "voxtype record start")
o.bind("F9", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })

o.bind("SUPER + CTRL + Z", "Zoom in", function()
  local zoom = hl.get_config("cursor.zoom_factor") or 1
  hl.config({ cursor = { zoom_factor = zoom + 1 } })
end)

o.bind("SUPER + CTRL + ALT + Z", "Reset zoom", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end)

o.bind("SUPER + CTRL + L", "Lock system", "omarchy-system-lock")
