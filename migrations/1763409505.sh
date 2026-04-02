echo "Add 10th workspace option to waybar config"

if ! grep -q '"10": "0",' ~/.config/waybar/config.jsonc; then
  sed -i '/"9": "9",/a\      "10": "0",' ~/.config/waybar/config.jsonc
fi
