echo "Update app launcher config to allow enough entries to show all keybindings on SUPER+K"

if ! grep "max_entries = 200" ~/.config/walker/config.toml; then
  omarchy-refresh-walker
fi
