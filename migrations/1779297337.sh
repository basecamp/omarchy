echo "Enable Voxtype keybindings toggle for existing installs"

if omarchy-cmd-present voxtype; then
  omarchy-hyprland-toggle voxtype on
fi
