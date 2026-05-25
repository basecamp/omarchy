# Set the default GDK_SCALE from what the monitor is currently reporting

scale=$(omarchy-hyprland-monitor-scaling)
sed -i -E "s|^local omarchy_gdk_scale = .*|local omarchy_gdk_scale = ${scale}|" "$HOME/.config/hypr/monitors.lua"
