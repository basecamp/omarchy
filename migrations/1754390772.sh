echo "Set SwayOSD max volume back to 100"

if ! grep -q "max_volume = 100" ~/.config/swayosd/config.toml; then
  sed -i 's/max_volume = 150/max_volume = 100/' ~/.config/swayosd/config.toml
  omarchy-restart-swayosd
fi
