echo "Increase Walker limit on how many entries can be shown to 256"

if ! grep -q "max_results" ~/.config/walker/config.toml; then
  sed -i "1i max_results = 256           # 256 should be enough for everyone" ~/.config/walker/config.toml
fi
