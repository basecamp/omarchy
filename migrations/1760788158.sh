echo "Copy config for wezterm so they're available as alternative terminal options"

if [[ ! -f ~/.config/wezterm/wezterm.lua ]]; then
  mkdir -p ~/.config/wezterm
  cp -Rpf $OMARCHY_PATH/config/wezterm/wezterm.lua ~/.config/wezterm/wezterm.lua
fi
