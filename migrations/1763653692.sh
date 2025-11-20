echo "Replace Waybar dock icon with something more obvious"

sed -i 's/"format": ""/"format": ""/' ~/.config/waybar/config.jsonc
omarchy-restart-waybar
