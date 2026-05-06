echo "Configure ghui with system theming"

if [[ ! -f ~/.config/ghui/config.json ]]; then
  mkdir -p ~/.config/ghui
  cp $OMARCHY_PATH/config/ghui/config.json ~/.config/ghui/config.json
fi
