echo "Add UWSM env"

export PATH="$HOME/.local/share/omarchy/bin:$PATH"

mkdir -p "$HOME/.config/uwsm/"
omarchy-refresh-config uwsm/env
omarchy-state set relaunch-required
