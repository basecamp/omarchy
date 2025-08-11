echo "Add UWSM env"

export OMARCHY_PATH="$HOME/.local/share/omarchy"
export PATH="$OMARCHY_PATH/bin:$PATH"

mkdir -p "$HOME/.config/uwsm/"
omarchy-refresh-config uwsm/env

echo -e "\n\e[31mOmarchy has a new PATH. You must immediately relaunch Hyprland or most Omarchy cmds won't work.\nPlease run Omarchy > Update again after the quick relaunch is complete.\e[0m"
echo
gum confirm "Ready to relaunch Hyprland? (All applications will be closed)" && uwsm stop
