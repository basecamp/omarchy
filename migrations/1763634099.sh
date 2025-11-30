echo "Using 󰂱 icon for bluetooth when connected"

sed -i 's/"format-connected": "",/"format-connected": "󰂱",/' ~/.config/waybar/config.jsonc
