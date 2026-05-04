echo "Replace Waybar dock icon with something more obvious"

sed -i 's/"format": ""/"format": ""/' ~/.config/waybar/config.jsonc
sed -i '/#custom-expand-icon {/,/}/ s/margin-right: 20px;/margin-right: 18px;/' ~/.config/waybar/style.css
omarchy-restart-waybar
