o.bind("SUPER + SPACE", "Launch apps", "omarchy-launch-walker")
o.bind("SUPER + CTRL + E", "Emoji picker", "omarchy-launch-walker -m symbols")
o.bind("SUPER + CTRL + C", "Capture menu", "omarchy-menu capture")
o.bind("SUPER + CTRL + O", "Toggle menu", "omarchy-menu toggle")
o.bind("SUPER + CTRL + H", "Hardware menu", "omarchy-menu hardware")
o.bind("SUPER + ALT + SPACE", "Omarchy menu", "omarchy-menu")
o.bind("SUPER + SHIFT + code:201", "Omarchy menu", "omarchy-menu")
o.bind("SUPER + ESCAPE", "System menu", "omarchy-menu system")
o.bind("XF86PowerOff", "Power menu", "omarchy-menu system", { locked = true })
o.bind("SUPER + K", "Show key bindings", "omarchy-menu-keybindings")
o.bind("SUPER + ALT + K", "Show Tmux key bindings", "omarchy-menu-tmux-keybindings")
o.bind("XF86Calculator", "Calculator", "gnome-calculator")

o.bind("SUPER + SHIFT + SPACE", "Toggle top bar", "omarchy-toggle-waybar")
o.bind("SUPER + SHIFT + CTRL + UP", "Move Waybar to top", "omarchy-style-waybar-position top")
o.bind("SUPER + SHIFT + CTRL + DOWN", "Move Waybar to bottom", "omarchy-style-waybar-position bottom")
o.bind("SUPER + SHIFT + CTRL + LEFT", "Move Waybar to left", "omarchy-style-waybar-position left")
o.bind("SUPER + SHIFT + CTRL + RIGHT", "Move Waybar to right", "omarchy-style-waybar-position right")
o.bind("SUPER + CTRL + SPACE", "Background switcher", "omarchy-menu background")
o.bind("SUPER + SHIFT + CTRL + SPACE", "Theme menu", "omarchy-menu theme")
o.bind("SUPER + BACKSPACE", "Toggle window transparency", "omarchy-hyprland-window-transparency-toggle")
o.bind("SUPER + SHIFT + BACKSPACE", "Toggle window gaps", "omarchy-hyprland-window-gaps-toggle")
o.bind("SUPER + CTRL + BACKSPACE", "Toggle single-window square aspect", "omarchy-hyprland-window-single-square-aspect-toggle")

o.bind("SUPER + COMMA", "Dismiss last notification", "makoctl dismiss")
o.bind("SUPER + SHIFT + COMMA", "Dismiss all notifications", "makoctl dismiss --all")
o.bind("SUPER + CTRL + COMMA", "Toggle silencing notifications", "omarchy-toggle-notification-silencing")
o.bind("SUPER + ALT + COMMA", "Invoke last notification", "makoctl invoke")
o.bind("SUPER + SHIFT + ALT + COMMA", "Restore last notification", "makoctl restore")

o.bind("SUPER + CTRL + I", "Toggle locking on idle", "omarchy-toggle-idle")
o.bind("SUPER + CTRL + N", "Toggle nightlight", "omarchy-toggle-nightlight")
o.bind("SUPER + CTRL + Delete", "Toggle laptop display", "omarchy-hyprland-monitor-internal toggle")
o.bind("SUPER + CTRL + ALT + Delete", "Toggle laptop display mirroring", "omarchy-hyprland-monitor-internal-mirror toggle")
o.bind("switch:on:Lid Switch", nil, "omarchy-hw-external-monitors && omarchy-hyprland-monitor-internal off", { locked = true })
o.bind("switch:off:Lid Switch", nil, "omarchy-hyprland-monitor-internal on", { locked = true })

o.bind("PRINT", "Screenshot", "omarchy-capture-screenshot")
o.bind("ALT + PRINT", "Screenrecording", "omarchy-menu screenrecord")
o.bind("SUPER + PRINT", "Color picker", "pkill hyprpicker || hyprpicker -a")
o.bind("SUPER + CTRL + PRINT", "Extract text (OCR) from screenshot", "omarchy-capture-text-extraction")

o.bind("SUPER + CTRL + S", "Share", "omarchy-menu share")

o.bind("SUPER + CTRL + PERIOD", "Transcode", "omarchy-transcode")

o.bind("SUPER + CTRL + R", "Set reminder", "omarchy-menu reminder-set")
o.bind("SUPER + CTRL + ALT + R", "Show reminders", "omarchy-reminder show")
o.bind("SUPER + SHIFT + CTRL + R", "Clear reminders", "omarchy-reminder clear")

o.bind("SUPER + CTRL + ALT + T", "Show time", [[notify-send -u low "    $(date +"%A %H:%M  ·  %d %B %Y  ·  Week %V")"]])
o.bind("SUPER + CTRL + ALT + B", "Show battery remaining", [[notify-send -u low "$(omarchy-battery-status)"]])
o.bind("SUPER + CTRL + ALT + W", "Show weather", [[notify-send -u low "$(omarchy-weather-status)"]])

o.bind("SUPER + CTRL + A", "Audio controls", "omarchy-launch-audio")
o.bind("SUPER + CTRL + B", "Bluetooth controls", "omarchy-launch-bluetooth")
o.bind("SUPER + CTRL + W", "Wifi controls", "omarchy-launch-wifi")
o.bind("SUPER + CTRL + T", "Activity", "omarchy-launch-tui btop")

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
