echo "Pin waybar battery module to BAT0 to prevent crash on HID battery disconnect"

CONFIG_FILE=~/.config/waybar/config.jsonc

if [[ -f "$CONFIG_FILE" ]] && ! grep -q '"bat":' "$CONFIG_FILE"; then
  sed -i '/"battery": {/a\    "bat": "BAT0",' "$CONFIG_FILE"
  omarchy-restart-waybar
fi
