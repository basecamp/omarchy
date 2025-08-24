echo "Add minimal starship prompt to terminal"

if ! command -v starship &>/dev/null; then
  sudo pacman -S --noconfirm starship
  cp $OMARCHY_PATH/config/starship.toml ~/.config/starship.toml
fi
