echo "Ignore empty passwords on lock screen"

if ! grep -q "ignore_empty_input" ~/.config/hypr/hyprlock.conf; then
  sed -i "/source =/a\ \ngeneral {\n    ignore_empty_input = true\n}" ~/.config/hypr/hyprlock.conf
fi
