echo "Add clipboard state management to waybar"

CONFIG=~/.config/waybar/config.jsonc
STYLE=~/config/waybar/style.css
if ! grep -q '"custom/clipboard"' "$CONFIG"; then
  sed -i '/"group\/tray-expander",/a\    "custom/clipboard",' "$CONFIG"
  sed -i '/"interval": 21600/a\  },\n  "custom/clipboard": {\n    "exec": "omarchy-clipboard-state get",\n    "signal": 9,\n    "on-click": "omarchy-clipboard-state toggle",\n    "on-click-right": "omarchy-launch-walker -m clipboard"' "$CONFIG"
  sed -i '0,/#custom-update {/{s/#custom-update {/#custom-update,\n#custom-clipboard {/}' "$STYLE"
  omarchy-restart-waybar
fi
