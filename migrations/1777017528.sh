echo "Show battery status notification on right-click of the waybar battery icon"

if ! grep -q 'omarchy-battery-status' ~/.config/waybar/config.jsonc; then
  sed -i '/"on-click": "omarchy-menu power",/a\    "on-click-right": "notify-send -u low \\"$(omarchy-battery-status)\\"",' ~/.config/waybar/config.jsonc
  omarchy-restart-waybar
fi
