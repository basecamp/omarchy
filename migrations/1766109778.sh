echo "Add interactive calendar (calcurse)"

# Install dependency
omarchy-pkg-add calcurse

# Add calendar to clock click ONLY if not already customized
WAYBAR_CFG="$HOME/.config/waybar/config.jsonc"

if [ -f "$WAYBAR_CFG" ]; then
  if ! grep -q "omarchy-launch-or-focus-tui calendar" "$WAYBAR_CFG"; then
    echo "Patching Waybar clock click to open calendar"

    # Replace existing on-click if present
    sed -i \
      's|"on-click":[^,]*|"on-click": "omarchy-launch-or-focus-tui calendar"|' \
      "$WAYBAR_CFG"
  fi
fi

# Reload UI
hyprctl reload 2>/dev/null || true
pkill waybar || true
