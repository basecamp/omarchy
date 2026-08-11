require("default.hypr.bindings_defaults")

o.bind(omarchy_bindings.close_window, "Close window", hl.dsp.window.close())
o.bind(omarchy_bindings.close_all_windows, "Close all windows", "omarchy-hyprland-window-close-all")

o.bind(omarchy_bindings.toggle_window_split, "Toggle window split", hl.dsp.layout("togglesplit"))
o.bind(omarchy_bindings.pseudo_window, "Pseudo window", hl.dsp.window.pseudo())
o.bind(omarchy_bindings.toggle_window_floating_tiling, "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
o.bind(omarchy_bindings.full_screen, "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
o.bind(omarchy_bindings.tiled_full_screen, "Tiled full screen", "omarchy-hyprland-window-tiled-fullscreen-toggle")
o.bind(omarchy_bindings.full_width, "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))
o.bind(omarchy_bindings.pop_window_out_float_pin, "Pop window out (float & pin)", "omarchy-hyprland-window-pop")
o.bind(omarchy_bindings.save_window_width, "Save window width", "omarchy-hyprland-window-width save")
o.bind(omarchy_bindings.restore_window_width, "Restore window width", "omarchy-hyprland-window-width restore")
o.bind(omarchy_bindings.toggle_workspace_layout, "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")

o.bind(omarchy_bindings.focus_on_left_window, "Focus on left window", hl.dsp.focus({ direction = "l" }))
o.bind(omarchy_bindings.focus_on_right_window, "Focus on right window", hl.dsp.focus({ direction = "r" }))
o.bind(omarchy_bindings.focus_on_above_window, "Focus on above window", hl.dsp.focus({ direction = "u" }))
o.bind(omarchy_bindings.focus_on_below_window, "Focus on below window", hl.dsp.focus({ direction = "d" }))

for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  o.bind(omarchy_bindings["switch_to_workspace_" .. workspace], "Switch to workspace " .. workspace, hl.dsp.focus({ workspace = tostring(workspace) }))
  o.bind(omarchy_bindings["move_window_to_workspace_" .. workspace], "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
  o.bind(omarchy_bindings["move_window_silently_to_workspace_" .. workspace], "Move window silently to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace), follow = false }))
end

o.bind(omarchy_bindings.toggle_scratchpad, "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
o.bind(omarchy_bindings.move_window_to_scratchpad, "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

o.bind(omarchy_bindings.next_workspace, "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
o.bind(omarchy_bindings.previous_workspace, "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
o.bind(omarchy_bindings.former_workspace, "Former workspace", hl.dsp.focus({ workspace = "previous" }))

o.bind(omarchy_bindings.move_workspace_to_left_monitor, "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
o.bind(omarchy_bindings.move_workspace_to_right_monitor, "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))
o.bind(omarchy_bindings.move_workspace_to_up_monitor, "Move workspace to up monitor", hl.dsp.workspace.move({ monitor = "u" }))
o.bind(omarchy_bindings.move_workspace_to_down_monitor, "Move workspace to down monitor", hl.dsp.workspace.move({ monitor = "d" }))

o.bind(omarchy_bindings.swap_window_to_the_left, "Swap window to the left", hl.dsp.window.swap({ direction = "l" }))
o.bind(omarchy_bindings.swap_window_to_the_right, "Swap window to the right", hl.dsp.window.swap({ direction = "r" }))
o.bind(omarchy_bindings.swap_window_up, "Swap window up", hl.dsp.window.swap({ direction = "u" }))
o.bind(omarchy_bindings.swap_window_down, "Swap window down", hl.dsp.window.swap({ direction = "d" }))

o.bind(omarchy_bindings.focus_on_next_window, "Focus on next window", hl.dsp.window.cycle_next())
o.bind(omarchy_bindings.focus_on_previous_window, "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))
o.bind(omarchy_bindings.reveal_active_window_on_top, "Reveal active window on top", hl.dsp.window.bring_to_top())
o.bind(omarchy_bindings.reveal_active_window_on_top_1, "Reveal active window on top", hl.dsp.window.bring_to_top())

o.bind(omarchy_bindings.focus_on_next_monitor, "Focus on next monitor", hl.dsp.focus({ monitor = "+1" }))
o.bind(omarchy_bindings.focus_on_previous_monitor, "Focus on previous monitor", hl.dsp.focus({ monitor = "-1" }))

o.bind(omarchy_bindings.expand_window_left, "Expand window left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
o.bind(omarchy_bindings.shrink_window_left, "Shrink window left", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
o.bind(omarchy_bindings.shrink_window_up, "Shrink window up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
o.bind(omarchy_bindings.expand_window_down, "Expand window down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))

o.bind(omarchy_bindings.expand_window_left_a_little, "Expand window left a little", hl.dsp.window.resize({ x = -25, y = 0, relative = true }))
o.bind(omarchy_bindings.shrink_window_left_a_little, "Shrink window left a little", hl.dsp.window.resize({ x = 25, y = 0, relative = true }))
o.bind(omarchy_bindings.shrink_window_up_a_little, "Shrink window up a little", hl.dsp.window.resize({ x = 0, y = -25, relative = true }))
o.bind(omarchy_bindings.expand_window_down_a_little, "Expand window down a little", hl.dsp.window.resize({ x = 0, y = 25, relative = true }))

o.bind(omarchy_bindings.expand_window_left_a_lot, "Expand window left a lot", hl.dsp.window.resize({ x = -300, y = 0, relative = true }))
o.bind(omarchy_bindings.shrink_window_left_a_lot, "Shrink window left a lot", hl.dsp.window.resize({ x = 300, y = 0, relative = true }))
o.bind(omarchy_bindings.shrink_window_up_a_lot, "Shrink window up a lot", hl.dsp.window.resize({ x = 0, y = -300, relative = true }))
o.bind(omarchy_bindings.expand_window_down_a_lot, "Expand window down a lot", hl.dsp.window.resize({ x = 0, y = 300, relative = true }))

o.bind(omarchy_bindings.scroll_active_workspace_forward, "Scroll active workspace forward", hl.dsp.focus({ workspace = "e+1" }))
o.bind(omarchy_bindings.scroll_active_workspace_backward, "Scroll active workspace backward", hl.dsp.focus({ workspace = "e-1" }))

o.bind(omarchy_bindings.move_window, "Move window", hl.dsp.window.drag(),  { mouse = true })
o.bind(omarchy_bindings.resize_window, "Resize window", hl.dsp.window.resize(),  { mouse = true })

o.bind(omarchy_bindings.toggle_window_grouping, "Toggle window grouping", hl.dsp.group.toggle())
o.bind(omarchy_bindings.move_active_window_out_of_group, "Move active window out of group", hl.dsp.window.move({ out_of_group = true }))

o.bind(omarchy_bindings.move_window_to_group_on_left, "Move window to group on left", hl.dsp.window.move({ into_group = "l" }))
o.bind(omarchy_bindings.move_window_to_group_on_right, "Move window to group on right", hl.dsp.window.move({ into_group = "r" }))
o.bind(omarchy_bindings.move_window_to_group_on_top, "Move window to group on top", hl.dsp.window.move({ into_group = "u" }))
o.bind(omarchy_bindings.move_window_to_group_on_bottom, "Move window to group on bottom", hl.dsp.window.move({ into_group = "d" }))

o.bind(omarchy_bindings.next_window_in_group, "Next window in group", hl.dsp.group.next())
o.bind(omarchy_bindings.previous_window_in_group, "Previous window in group", hl.dsp.group.prev())

o.bind(omarchy_bindings.move_grouped_window_focus_left, "Move grouped window focus left", hl.dsp.group.prev())
o.bind(omarchy_bindings.move_grouped_window_focus_right, "Move grouped window focus right", hl.dsp.group.next())

o.bind(omarchy_bindings.next_window_in_group_2, "Next window in group", hl.dsp.group.next())
o.bind(omarchy_bindings.previous_window_in_group_3, "Previous window in group", hl.dsp.group.prev())

for index = 1, 5 do
  o.bind(omarchy_bindings["switch_to_group_window_" .. index], "Switch to group window " .. index, hl.dsp.group.active({ index = index }))
end

o.bind(omarchy_bindings.monitor_scaling_up, "Monitor scaling up", "omarchy-hyprland-monitor-scaling up")
o.bind(omarchy_bindings.monitor_scaling_down, "Monitor scaling down", "omarchy-hyprland-monitor-scaling down")
