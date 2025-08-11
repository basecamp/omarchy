echo "Add UWSM env"
mkdir -p "$HOME/.config/uwsm/"
omarchy-refresh-config uwsm/env
export PATH="$HOME/.local/share/omarchy/bin:$PATH"
omarchy-state set relaunch-required
