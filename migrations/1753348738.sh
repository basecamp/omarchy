echo "Add copy on selection to Alacritty configuration"

ALACRITTY_CONFIG="$HOME/.config/alacritty/alacritty.toml"

if [ -f "$ALACRITTY_CONFIG" ]; then
  if ! grep -q '^\[selection\]' "$ALACRITTY_CONFIG"; then
    # Find the line with [keyboard] and insert [selection] section before it
    sed -i '/^\[keyboard\]/i \
[selection]\
save_to_clipboard = true\
' "$ALACRITTY_CONFIG"
    echo "Added copy on selection to Alacritty configuration"
  else
    echo "Selection section already exists in Alacritty configuration"
  fi
else
  echo "Alacritty configuration not found at $ALACRITTY_CONFIG"
fi