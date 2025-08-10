echo "Add UWSM env"
mkdir -p "$HOME/.config/uwsm/"
omarchy-refresh-config uwsm/env

omarchy-state set relaunch-required
