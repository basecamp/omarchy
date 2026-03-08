echo "Add Shift+Return keyboard binding for multi-line as used by Claude Code to Alacritty"

ALACRITTY_CONFIG=~/.config/alacritty/alacritty.toml

if [[ -f $ALACRITTY_CONFIG ]] && ! grep -q 'key = "Return"' "$ALACRITTY_CONFIG"; then
  sed -i 's/{ key = "Insert", mods = "Control", action = "Copy" }/{ key = "Insert", mods = "Control", action = "Copy" },\n  { key = "Return", mods = "Shift", chars = "\\u001B\\r" }/' "$ALACRITTY_CONFIG"
fi
