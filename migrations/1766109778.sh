echo "Add interactive calendar (calcurse)"

omarchy-pkg-add calcurse

WAYBAR_CFG="$HOME/.config/waybar/config.jsonc"

if [ -f "$WAYBAR_CFG" ]; then
  if ! grep -q "omarchy-launch-or-focus-tui calcurse" "$WAYBAR_CFG"; then
    echo "Patching Waybar clock click to open calendar"

    sed -i 's|"on-click-right": "omarchy-launch-floating-terminal-with-presentation omarchy-tz-select"|"on-click-right": "omarchy-launch-or-focus-tui calcurse"|' "$WAYBAR_CFG"
  fi
fi

omarchy-restart-waybar
