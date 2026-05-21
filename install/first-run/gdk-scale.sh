# Persist the detected monitor scale (and matching GDK_SCALE) into
# ~/.config/hypr/monitors.lua. omarchy-hyprland-monitor-scaling with no args
# returns the closest preset to whatever Hyprland chose at startup; passing
# that value back in updates both `omarchy_monitor_scale` and
# `omarchy_gdk_scale` in the lua config so the choice survives a reboot.
scale=$(omarchy-hyprland-monitor-scaling 2>/dev/null || true)
[[ -n $scale ]] || exit 0
omarchy-hyprland-monitor-scaling "$scale" >/dev/null 2>&1 || true
