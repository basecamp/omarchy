#!/bin/bash

# Fix Waybar clock timezone to use system local time instead of UTC
# See: https://github.com/basecamp/omarchy/issues/5380

echo "Fixing Waybar clock timezone..."

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"

if [[ ! -f "$WAYBAR_CONFIG" ]]; then
  echo "Waybar config not found, skipping..."
  exit 0
fi

# Check if timezone is already configured
if grep -q '"timezone"' "$WAYBAR_CONFIG"; then
  echo "Timezone already configured in Waybar"
  exit 0
fi

# Get system timezone
SYSTEM_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "")

# Backup the config
cp "$WAYBAR_CONFIG" "${WAYBAR_CONFIG}.bak"

# Use awk to safely insert timezone (handles / in timezone names)
awk -v tz="$SYSTEM_TZ" '
  /"clock":/ { found=1 }
  found && /"format":/ && !inserted {
    print "    \"timezone\": \"" tz "\","
    inserted=1
  }
  { print }
' "$WAYBAR_CONFIG" > "${WAYBAR_CONFIG}.new"

mv "${WAYBAR_CONFIG}.new" "$WAYBAR_CONFIG"

echo "Waybar clock timezone fix complete!"
omarchy-restart-waybar 2>/dev/null || true
