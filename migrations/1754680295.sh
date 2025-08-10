echo "Add UWSM env"
mkdir -p "$HOME/.config/uwsm/"
omarchy-refresh-config uwsm/env

gum confirm "UWSM env has been updated and a relaunch of Hyprland is required to apply the changes. Would you like to relaunch Hyprland now?" && uwsm stop
