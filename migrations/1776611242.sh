echo "Install socat for the Hyprland monitor event watcher"

omarchy-pkg-add socat
uwsm-app -- omarchy-hyprland-monitor-watch &
