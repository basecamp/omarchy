echo "Add full OSC 52 support to Alacritty"

ALACRITTY_CONFIG=~/.config/alacritty/alacritty.toml

if [[ -f $ALACRITTY_CONFIG ]] && ! grep -q 'osc52' "$ALACRITTY_CONFIG"; then
  cat >> "$ALACRITTY_CONFIG" << 'EOF'

[terminal]
osc52 = "CopyPaste"
EOF
fi
