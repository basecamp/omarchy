# Set the default GDK_SCALE from what the monitor is currently reporting

sed -i -E "s|^([[:space:]]*env[[:space:]]*=[[:space:]]*GDK_SCALE,).*|\\1$(omarchy-hyprland-monitor-scale)|" ~/.config/hypr/monitors.conf
