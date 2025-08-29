echo "Add minimal starship prompt to terminal"

if cmd-missing starship; then
  pkg-add starship
  cp $OMARCHY_PATH/config/starship.toml ~/.config/starship.toml
fi
