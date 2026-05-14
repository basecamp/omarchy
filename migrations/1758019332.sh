echo "Set \$TERMINAL and \$EDITOR in ~/.config/uwsm/default so entire system can rely on it"

# Set terminal and editor default in uwsm
omarchy-refresh-config uwsm/default
omarchy-refresh-config uwsm/env
omarchy-state set reboot-required
