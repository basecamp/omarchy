echo "Ensure .config/hypr/looknfeel.lua is available"

if [[ ! -f ~/.config/hypr/looknfeel.lua ]]; then
  cp "$OMARCHY_PATH/config/hypr/looknfeel.lua" ~/.config/hypr/looknfeel.lua
fi
