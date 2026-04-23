echo "Install socat so we can reactivate internal display when external display is removed"

omarchy-pkg-add socat
uwsm-app -- omarchy-hyprland-monitor-watch &
