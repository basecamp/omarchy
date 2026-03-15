echo "Copy config for wezterm so it's available as an alternative terminal option"

if [[ ! -f ~/.config/wezterm/wezterm.lua ]]; then
  mkdir -p ~/.config/wezterm
  cp -Rpf $OMARCHY_PATH/config/wezterm/wezterm.lua ~/.config/wezterm/wezterm.lua
fi

# Ensure the current Omarchy theme (including wezterm.lua) is generated
if command -v omarchy-theme-refresh >/dev/null 2>&1; then
  omarchy-theme-refresh
fi
