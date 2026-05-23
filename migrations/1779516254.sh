echo "Update elephant symbols paste shortcut for Hyprland 0.55"

symbols_config=~/.config/elephant/symbols.toml

if [[ -f $symbols_config ]]; then
  sed -i 's/hyprctl dispatch sendshortcut "SHIFT, Insert,"/hyprctl dispatch sendshortcut "SHIFT,Insert,activewindow"/' "$symbols_config"
else
  omarchy-refresh-config elephant/symbols.toml
fi

omarchy-restart-walker
