echo "Increase Walker limit on how many entries can be shown to 256"

if ! grep -q "max_results" ~/.config/walker/config.toml; then
  sed -i '/^\[providers\]$/a max_results = 256' ~/.config/walker/config.toml
fi
