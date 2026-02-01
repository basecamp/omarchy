echo "Improve audio controls icon for default selection"

if [[ ! -f ~/.config/wiremix/wiremix.toml ]]; then
  mkdir -p ~/.config/wiremix
  cp -f $OMARCHY_PATH/config/wiremix/wiremix.toml ~/.config/wiremix/
fi
