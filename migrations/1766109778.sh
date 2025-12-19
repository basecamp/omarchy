echo "Add interactive calendar (calcurse)"

# Install dependency
omarchy-pkg-add calcurse

# Add calendar to clock click ONLY if not already present
WAYBAR_CFG="$HOME/.config/waybar/config.jsonc"

if [ -f "$WAYBAR_CFG" ]; then
  if ! grep -q "omarchy-launch-or-focus-tui calcurse" "$WAYBAR_CFG"; then
    echo "Patching Waybar clock click to open calendar"

    # Replace existing on-click-right with calcurse (following migration 1762121828.sh pattern)
    sed -i 's|"on-click-right": "omarchy-launch-floating-terminal-with-presentation omarchy-tz-select"|"on-click-right": "omarchy-launch-or-focus-tui calcurse"|' "$WAYBAR_CFG"
  fi
fi

# Reload UI
omarchy-restart-waybar
