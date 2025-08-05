echo "Change update-available icon in top bar from  to "
if grep -q '"format": "",' ~/.config/waybar/config.jsonc; then
  sed -i 's/"format": ""/"format": ""/' ~/.config/waybar/config.jsonc
fi
