echo "Add full OSC 52 support to Alacritty"

ALACRITTY_CONFIG=~/.config/alacritty/alacritty.toml

if [[ -f $ALACRITTY_CONFIG ]]; then
  if ! grep -q '^[[:space:]]*osc52[[:space:]]*=' "$ALACRITTY_CONFIG"; then
    {
      echo
      echo "[terminal]"
      echo "osc52 = \"CopyPaste\""
    } >> "$ALACRITTY_CONFIG"
  fi
fi
