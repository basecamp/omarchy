echo "Add minimal starship prompt to terminal"

if omarchy-cmd-missing starship; then
  omarchy-pkg-add starship
  cp $OMARCHY_PATH/config/starship.toml ~/.config/starship.toml
fi
