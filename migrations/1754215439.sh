echo "Update app launcher config to allow enough entries to show all keybindings on SUPER+K"

if ! grep "max_entries = 200" ~/.config/walker/config.toml; then
  ~/.local/share/omarchy/bin/omarchy-refresh-walker
fi
