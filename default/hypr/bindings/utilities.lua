hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("omarchy-launch-walker"), { description = "Launch apps" })
hl.bind("SUPER + CTRL + E", hl.dsp.exec_cmd("omarchy-launch-walker -m symbols"), { description = "Emoji picker" })
hl.bind("SUPER + CTRL + C", hl.dsp.exec_cmd("omarchy-menu capture"), { description = "Capture menu" })
hl.bind("SUPER + CTRL + O", hl.dsp.exec_cmd("omarchy-menu toggle"), { description = "Toggle menu" })
hl.bind("SUPER + CTRL + H", hl.dsp.exec_cmd("omarchy-menu hardware"), { description = "Hardware menu" })
hl.bind("SUPER + ALT + SPACE", hl.dsp.exec_cmd("omarchy-menu"), { description = "Omarchy menu" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("omarchy-menu"), { description = "Omarchy menu" })
hl.bind("SUPER + ESCAPE", hl.dsp.exec_cmd("omarchy-menu system"), { description = "System menu" })
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("omarchy-menu system"), { locked = true, description = "Power menu" })
hl.bind("SUPER + K", hl.dsp.exec_cmd("omarchy-menu-keybindings"), { description = "Show key bindings" })
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("omarchy-menu-tmux-keybindings"), { description = "Show Tmux key bindings" })
hl.bind("XF86Calculator", hl.dsp.exec_cmd("gnome-calculator"), { description = "Calculator" })

hl.bind("SUPER + SHIFT + SPACE", hl.dsp.exec_cmd("omarchy-toggle-waybar"), { description = "Toggle top bar" })
hl.bind("SUPER + SHIFT + CTRL + UP", hl.dsp.exec_cmd("omarchy-style-waybar-position top"), { description = "Move Waybar to top" })
hl.bind("SUPER + SHIFT + CTRL + DOWN", hl.dsp.exec_cmd("omarchy-style-waybar-position bottom"), { description = "Move Waybar to bottom" })
hl.bind("SUPER + SHIFT + CTRL + LEFT", hl.dsp.exec_cmd("omarchy-style-waybar-position left"), { description = "Move Waybar to left" })
hl.bind("SUPER + SHIFT + CTRL + RIGHT", hl.dsp.exec_cmd("omarchy-style-waybar-position right"), { description = "Move Waybar to right" })
hl.bind("SUPER + CTRL + SPACE", hl.dsp.exec_cmd("omarchy-menu background"), { description = "Background switcher" })
hl.bind("SUPER + SHIFT + CTRL + SPACE", hl.dsp.exec_cmd("omarchy-menu theme"), { description = "Theme menu" })
hl.bind("SUPER + BACKSPACE", hl.dsp.exec_cmd("omarchy-hyprland-window-transparency-toggle"), { description = "Toggle window transparency" })
hl.bind("SUPER + SHIFT + BACKSPACE", hl.dsp.exec_cmd("omarchy-hyprland-window-gaps-toggle"), { description = "Toggle window gaps" })
hl.bind("SUPER + CTRL + BACKSPACE", hl.dsp.exec_cmd("omarchy-hyprland-window-single-square-aspect-toggle"), { description = "Toggle single-window square aspect" })

hl.bind("SUPER + COMMA", hl.dsp.exec_cmd("makoctl dismiss"), { description = "Dismiss last notification" })
hl.bind("SUPER + SHIFT + COMMA", hl.dsp.exec_cmd("makoctl dismiss --all"), { description = "Dismiss all notifications" })
hl.bind("SUPER + CTRL + COMMA", hl.dsp.exec_cmd("omarchy-toggle-notification-silencing"), { description = "Toggle silencing notifications" })
hl.bind("SUPER + ALT + COMMA", hl.dsp.exec_cmd("makoctl invoke"), { description = "Invoke last notification" })
hl.bind("SUPER + SHIFT + ALT + COMMA", hl.dsp.exec_cmd("makoctl restore"), { description = "Restore last notification" })

hl.bind("SUPER + CTRL + I", hl.dsp.exec_cmd("omarchy-toggle-idle"), { description = "Toggle locking on idle" })
hl.bind("SUPER + CTRL + N", hl.dsp.exec_cmd("omarchy-toggle-nightlight"), { description = "Toggle nightlight" })
hl.bind("SUPER + CTRL + Delete", hl.dsp.exec_cmd("omarchy-hyprland-monitor-internal toggle"), { description = "Toggle laptop display" })
hl.bind("SUPER + CTRL + ALT + Delete", hl.dsp.exec_cmd("omarchy-hyprland-monitor-internal-mirror toggle"), { description = "Toggle laptop display mirroring" })
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("omarchy-hw-external-monitors && omarchy-hyprland-monitor-internal off"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("omarchy-hyprland-monitor-internal on"), { locked = true })

hl.bind("PRINT", hl.dsp.exec_cmd("omarchy-capture-screenshot"), { description = "Screenshot" })
hl.bind("ALT + PRINT", hl.dsp.exec_cmd("omarchy-menu screenrecord"), { description = "Screenrecording" })
hl.bind("SUPER + PRINT", hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a"), { description = "Color picker" })
hl.bind("SUPER + CTRL + PRINT", hl.dsp.exec_cmd("omarchy-capture-text-extraction"), { description = "Extract text (OCR) from screenshot" })

hl.bind("SUPER + CTRL + S", hl.dsp.exec_cmd("omarchy-menu share"), { description = "Share" })

hl.bind("SUPER + CTRL + PERIOD", hl.dsp.exec_cmd("omarchy-transcode"), { description = "Transcode" })

hl.bind("SUPER + CTRL + R", hl.dsp.exec_cmd("omarchy-menu reminder-set"), { description = "Set reminder" })
hl.bind("SUPER + CTRL + ALT + R", hl.dsp.exec_cmd("omarchy-reminder show"), { description = "Show reminders" })
hl.bind("SUPER + SHIFT + CTRL + R", hl.dsp.exec_cmd("omarchy-reminder clear"), { description = "Clear reminders" })

hl.bind("SUPER + CTRL + ALT + T", hl.dsp.exec_cmd([[notify-send -u low "    $(date +"%A %H:%M  ·  %d %B %Y  ·  Week %V")"]]), { description = "Show time" })
hl.bind("SUPER + CTRL + ALT + B", hl.dsp.exec_cmd([[notify-send -u low "$(omarchy-battery-status)"]]), { description = "Show battery remaining" })
hl.bind("SUPER + CTRL + ALT + W", hl.dsp.exec_cmd([[notify-send -u low "$(omarchy-weather-status)"]]), { description = "Show weather" })

hl.bind("SUPER + CTRL + A", hl.dsp.exec_cmd("omarchy-launch-audio"), { description = "Audio controls" })
hl.bind("SUPER + CTRL + B", hl.dsp.exec_cmd("omarchy-launch-bluetooth"), { description = "Bluetooth controls" })
hl.bind("SUPER + CTRL + W", hl.dsp.exec_cmd("omarchy-launch-wifi"), { description = "Wifi controls" })
hl.bind("SUPER + CTRL + T", hl.dsp.exec_cmd("omarchy-launch-tui btop"), { description = "Activity" })

hl.bind("SUPER + CTRL + X", hl.dsp.exec_cmd("voxtype record toggle"), { description = "Toggle dictation" })
hl.bind("F9", hl.dsp.exec_cmd("voxtype record start"), { description = "Start dictation (push-to-talk)" })
hl.bind("F9", hl.dsp.exec_cmd("voxtype record stop"), { release = true, description = "Stop dictation (push-to-talk)" })

hl.bind("SUPER + CTRL + Z", function()
  local zoom = hl.get_config("cursor.zoom_factor") or 1
  hl.config({ cursor = { zoom_factor = zoom + 1 } })
end, { description = "Zoom in" })

hl.bind("SUPER + CTRL + ALT + Z", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end, { description = "Reset zoom" })

hl.bind("SUPER + CTRL + L", hl.dsp.exec_cmd("omarchy-system-lock"), { description = "Lock system" })
