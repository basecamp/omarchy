echo "Use Bluetooth off icon in the waybar when BlueTUI has turned off the adapter"

if ! grep -q '"format-off": "󰂲"' ~/.config/waybar/config.jsonc; then
  sed -i '/"format-disabled": "󰂲",/a\    "format-off": "󰂲",' ~/.config/waybar/config.jsonc
  omarchy-restart-waybar
fi
