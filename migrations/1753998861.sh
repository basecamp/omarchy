echo "Update Walker config to include . as the leader key for the finder"
if ! grep -q 'prefix = "\."' ~/.config/walker/config.toml; then
  ~/.local/share/omarchy/bin/omarchy-refresh-walker
fi
