#!/bin/bash

# This migration script adds the custom peripherals battery monitoring module to Waybar configuration.
# It creates a backup of the existing configuration before making changes.
# It checks for the existence of the module and its configuration to avoid duplicates.
# This should preserve custom waybar configurations - which are possibly plentiful.

CONFIG_FILE="$HOME/.config/waybar/config.jsonc"
BACKUP_FILE="$HOME/.config/waybar/config.jsonc.backup.$(date +%s)"
MODULE_NAME="custom/devices-battery"

# Check if waybar config exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Waybar config file not found at $CONFIG_FILE"
  exit 1
fi

# Create backup
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "Created backup at $BACKUP_FILE"

# Check if module already exists
if grep -q "\"$MODULE_NAME\"" "$CONFIG_FILE"; then
  echo "Module already exists in config, skipping..."
  exit 0
fi

echo "Adding $MODULE_NAME to waybar config..."

# Step 1: Add to modules-right array
# Find the line with "battery", (last item in modules-right) and add after it
awk '
    /"modules-right":/,/\]/ {
        if (/^[[:space:]]*"battery",[[:space:]]*$/) {
            print
            print "    \"custom/devices-battery\","
            next
        }
    }
    { print }
' "$CONFIG_FILE" >"$CONFIG_FILE.tmp"
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
echo "Added to modules-right array"

# Step 2: Add module configuration right after modules-right array closes
awk '
    BEGIN { in_modules_right = 0 }

    # Detect modules-right array
    /"modules-right":[[:space:]]*\[/ {
        in_modules_right = 1
        print
        next
    }

    # When we find the closing bracket of modules-right
    in_modules_right == 1 && /^[[:space:]]*\],?[[:space:]]*$/ {
        print
        print "  \"custom/devices-battery\": {"
        print "    \"exec\": \"omarchy-peripherals-battery-status\","
        print "    \"return-type\": \"json\","
        print "    \"interval\": 30,"
        print "    \"format\": \"{}\","
        print "    \"tooltip\": true"
        print "  },"
        in_modules_right = 0
        next
    }

    { print }
' "$CONFIG_FILE" >"$CONFIG_FILE.tmp"
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo "Added module configuration"
echo ""
echo "Migration complete!"
omarchy-refresh-waybar
