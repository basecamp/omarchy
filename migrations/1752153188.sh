echo "Migrate to the modular implementation of hyprlock"
if [ -L ~/.config/hypr/hyprlock.conf ]; then
  rm ~/.config/hypr/hyprlock.conf
  cp ~/.local/share/omarchy/config/hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf
fi
