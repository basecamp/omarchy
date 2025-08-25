echo "Add minimal starship prompt to terminal"

if ! command -v starship &>/dev/null; then
  sudo pacman -S --noconfirm starship
  ln -nsf $OMARCHY_PATH/config/starship/Default.toml $HOME/.config/starship.toml
fi
