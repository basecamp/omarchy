require("default.hypr.bindings_defaults")

o.bind(omarchy_bindings.omarchy_menu, "Omarchy menu", "omarchy-menu toggle")
o.bind(omarchy_bindings.apps_menu, "Apps menu", "omarchy-menu toggle apps")
o.bind(omarchy_bindings.emojis, "Emojis", "omarchy-shell shell toggle omarchy.emojis")
o.bind(omarchy_bindings.capture_menu, "Capture menu", "omarchy-menu toggle capture")
o.bind(omarchy_bindings.toggle_menu, "Toggle menu", "omarchy-menu toggle toggle")
o.bind(omarchy_bindings.hardware_menu, "Hardware menu", "omarchy-menu toggle hardware")
o.bind(omarchy_bindings.omarchy_menu_1, "Omarchy menu", "omarchy-menu toggle root")
o.bind(omarchy_bindings.system_menu, "System menu", "omarchy-menu toggle system")
o.bind(omarchy_bindings.power_menu, "Power menu", "omarchy-menu toggle system",  { locked = true })
o.bind(omarchy_bindings.keybindings, "Keybindings", "omarchy-menu-keybindings")
o.bind(omarchy_bindings.tmux_keybindings, "Tmux keybindings", "omarchy-menu-tmux-keybindings")
o.bind(omarchy_bindings.herdr_keybindings, "Herdr keybindings", "omarchy-menu-herdr-keybindings")
o.bind(omarchy_bindings.calculator, "Calculator", "omacalc")
o.bind(omarchy_bindings.calculator_2, "Calculator", "omacalc")

o.bind_toggle(omarchy_bindings.toggle_top_bar, "Toggle top bar", "bar")
o.bind(omarchy_bindings.background_switcher, "Background switcher", "omarchy-menu toggle background")
o.bind(omarchy_bindings.theme_menu, "Theme menu", "omarchy-menu toggle theme")
o.bind(omarchy_bindings.toggle_window_transparency, "Toggle window transparency", "omarchy-hyprland-window-transparency-toggle")
o.bind(omarchy_bindings.toggle_window_gaps, "Toggle window gaps", "omarchy-hyprland-window-gaps-toggle")
o.bind(omarchy_bindings.toggle_single_window_square_aspect, "Toggle single-window square aspect", "omarchy-hyprland-window-single-square-aspect-toggle")

-- xkbcommon names the comma keysym "comma"; the upper-case "COMMA" does not match.
o.bind(omarchy_bindings.dismiss_last_notification, "Dismiss last notification", "omarchy-shell notifications dismissOne")
o.bind(omarchy_bindings.dismiss_all_notifications, "Dismiss all notifications", "omarchy-shell notifications dismissAll")
o.bind_toggle(omarchy_bindings.toggle_silencing_notifications, "Toggle silencing notifications", "notification-silencing")
o.bind(omarchy_bindings.invoke_last_notification, "Invoke last notification", "omarchy-shell notifications invokeLast")
o.bind(omarchy_bindings.open_notification_history, "Open notification history", "omarchy-shell notifications showHistory")

o.bind_toggle(omarchy_bindings.toggle_locking_on_idle, "Toggle locking on idle", "idle")
o.bind_toggle(omarchy_bindings.toggle_nightlight, "Toggle nightlight", "nightlight")
o.bind(omarchy_bindings.toggle_laptop_display, "Toggle laptop display", "omarchy-hyprland-monitor-internal toggle")
o.bind(omarchy_bindings.toggle_laptop_display_mirroring, "Toggle laptop display mirroring", "omarchy-hyprland-monitor-internal-mirror toggle")
o.bind(omarchy_bindings.lid_switch_on or "switch:on:Lid Switch", nil, "omarchy-system-lid-close", { locked = true })
o.bind(omarchy_bindings.lid_switch_off or "switch:off:Lid Switch", nil, "omarchy-hyprland-monitor-clamshell", { locked = true })

o.bind(omarchy_bindings.screenshot, "Screenshot", "omarchy-capture-screenshot")
o.bind(omarchy_bindings.screenrecording, "Screenrecording", "omarchy-capture-screenrecording --stop-recording || omarchy-menu toggle trigger.capture.screenrecord")
o.bind(omarchy_bindings.make_webcam_overlay_smaller, "Make webcam overlay smaller", "omarchy-capture-webcam-resize smaller")
o.bind(omarchy_bindings.make_webcam_overlay_larger, "Make webcam overlay larger", "omarchy-capture-webcam-resize larger")
o.bind(omarchy_bindings.color_picker, "Color picker", "pkill hyprpicker || hyprpicker -a")
o.bind(omarchy_bindings.extract_text_ocr_from_screenshot, "Extract text (OCR) from screenshot", "omarchy-capture-text")

-- Keyboard control for the slurp region picker (see omarchy-capture-region).
-- The binds live exactly as long as a selection layer is on screen (slurp
-- opens one per monitor), so they cannot leak or get stuck.
-- Unbinding by key would take a same-key binding out of the user's own config
-- with it, so each handle is kept and removed individually.
local selection_layers = 0
local selection_binds = {}

hl.on("layer.opened", function(layer)
  if layer.namespace == "selection" then
    selection_layers = selection_layers + 1
    if selection_layers == 1 then
      selection_binds = {
        hl.bind("RETURN", hl.dsp.exec_cmd("omarchy-capture-region --take-window"), { description = "Capture highlighted window" }),
        hl.bind("CTRL + RETURN", hl.dsp.exec_cmd("omarchy-capture-region --take-fullscreen"), { description = "Capture entire screen" }),
        hl.bind("TAB", hl.dsp.exec_cmd("omarchy-capture-region --select-window next"), { description = "Select next window to capture" }),
        hl.bind("CTRL + TAB", hl.dsp.exec_cmd("omarchy-capture-region --select-window prev"), { description = "Select previous window to capture" }),
      }
      for _, direction in ipairs({ "left", "right", "up", "down" }) do
        table.insert(
          selection_binds,
          hl.bind(direction:upper(), hl.dsp.exec_cmd("omarchy-capture-region --select-window " .. direction), { description = "Select window to capture" })
        )
      end
    end
  end
end)

hl.on("layer.closed", function(layer)
  if layer.namespace == "selection" and selection_layers > 0 then
    selection_layers = selection_layers - 1
    if selection_layers == 0 then
      for _, keybind in ipairs(selection_binds) do
        keybind:unbind()
      end
      selection_binds = {}
    end
  end
end)

o.bind(omarchy_bindings.share, "Share", "omarchy-menu toggle share")

o.bind(omarchy_bindings.transcode, "Transcode", "omarchy-transcode")

o.bind(omarchy_bindings.set_reminder, "Set reminder", "omarchy-menu toggle reminder-set")
o.bind(omarchy_bindings.show_reminders, "Show reminders", "omarchy-reminder show")
o.bind(omarchy_bindings.clear_reminders, "Clear reminders", "omarchy-reminder clear")

o.bind(omarchy_bindings.show_time, "Show time", "omarchy-notification-time")
o.bind(omarchy_bindings.show_battery_remaining, "Show battery remaining", "omarchy-notification-battery")
o.bind(omarchy_bindings.toggle_weather, "Toggle weather", "omarchy-notification-weather")

o.bind(omarchy_bindings.agent, "Agent", "omarchy-launch-agent")
o.bind(omarchy_bindings.audio, "Audio", "omarchy-shell shell toggle omarchy.audio")
o.bind(omarchy_bindings.bluetooth, "Bluetooth", "omarchy-shell shell toggle omarchy.bluetooth")
o.bind(omarchy_bindings.display, "Display", "omarchy-shell shell toggle omarchy.monitor")
o.bind(omarchy_bindings.calendar_3, "Calendar", "omarchy-shell shell toggle omarchy.clock")
o.bind(omarchy_bindings.network, "Network", "omarchy-shell shell toggle omarchy.network")
o.bind(omarchy_bindings.power, "Power", "omarchy-shell shell toggle omarchy.power")
o.bind(omarchy_bindings.activity, "Activity", { tui = "btop" })

-- The letters above name a panel; the numbers count them. 1 is the leftmost
-- panel in the bar's right section, and a widget with no panel of its own (the
-- tray) is not counted, so the number matches the icon a user would point at.
-- A bar with fewer panels than this leaves the tail of the range doing nothing.
for panel = 1, 9 do
  o.bind(
    omarchy_bindings["bar_panel_" .. panel],
    "Bar panel " .. panel,
    "omarchy-shell -q shell togglePanelAt right " .. panel
  )
end

o.bind(omarchy_bindings.zoom_in, "Zoom in", function()
  local zoom = hl.get_config("cursor.zoom_factor") or 1
  hl.config({ cursor = { zoom_factor = zoom + 1 } })
end)

o.bind(omarchy_bindings.reset_zoom, "Reset zoom", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end)

o.bind(omarchy_bindings.lock_system, "Lock system", "omarchy-system-lock")
