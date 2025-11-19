echo "Hide Bluetooth module in waybar if there's no BT controller"

if ! grep -q "format-no-controller" ~/.config/waybar/config.jsonc; then
  sed -i '/format-connected": "",/a\    "format-no-controller": "",' ~/.config/waybar/config.jsonc
  omarchy-restart-waybar
fi
