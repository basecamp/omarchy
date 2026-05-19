echo "Switch lock screen authentication to Quickshell"

omarchy-setup-lock

rm -f ~/.local/state/omarchy/toggles/hyprlock.conf ~/.local/state/omarchy/toggles/lock.conf

rm -f ~/.config/hypr/hyprlock.conf ~/.config/omarchy/current/theme/hyprlock.conf

omarchy-pkg-drop hyprlock
