echo "Hide Bluetooth module in waybar if there's no BT controller"

sed -i '/format-connected": "",/a\    "format-no-controller": "",' ~/.config/waybar/config.jsonc
