echo "Add WezTerm terminal support"

# Copy WezTerm config to user's ~/.config if not already present
if [[ ! -f ~/.config/wezterm/wezterm.lua ]]; then
  mkdir -p ~/.config/wezterm
  cp "$OMARCHY_PATH/config/wezterm/wezterm.lua" ~/.config/wezterm/wezterm.lua
fi
