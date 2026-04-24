#!/bin/bash

# Fix Waybar clock timezone to use system local time instead of UTC
# See: https://github.com/basecamp/omarchy/issues/5380

echo "Fixing Waybar clock timezone..."

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"

if [[ -f "$WAYBAR_CONFIG" ]]; then
  # Check if timezone is already set
  if grep -q '"timezone"' "$WAYBAR_CONFIG"; then
    echo "Timezone already configured in Waybar"
  else
    # Get system timezone
    SYSTEM_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "")
    
    if [[ -n "$SYSTEM_TZ" ]]; then
      # Use sed to add timezone to clock config
      # Add timezone after the format line in the clock section
      sed -i "/\"clock\":/{
        n;s/\"format\"/\"timezone\": \"$SYSTEM_TZ\",\n    \"format\"/
      }" "$WAYBAR_CONFIG"
      echo "Added timezone '$SYSTEM_TZ' to Waybar clock config"
    else
      # Fallback: add empty timezone to use system local time
      sed -i "/\"clock\":/{
        n;s/\"format\"/\"timezone\": \"\",\n    \"format\"/
      }" "$WAYBAR_CONFIG"
      echo "Added empty timezone (will use system local time)"
    fi
    
    # Restart waybar to apply changes
    omarchy-restart-waybar 2>/dev/null || true
  fi
else
  echo "Waybar config not found at $WAYBAR_CONFIG"
fi

echo "Waybar clock timezone fix complete!"
