echo "Copy config for wezterm so it's available as an alternative terminal option"

if [[ ! -f ~/.config/wezterm/wezterm.lua ]]; then
  mkdir -p ~/.config/wezterm
  cp -Rpf $OMARCHY_PATH/config/wezterm/wezterm.lua ~/.config/wezterm/wezterm.lua
fi
