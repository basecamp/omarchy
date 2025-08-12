#!/bin/bash

# Migration: Add Zed editor theme support
# This migration sets up Zed theme integration with pre-generated theme files

echo "🎨 Adding Zed editor theme support..."

# Setup Zed theme link if Zed is installed
if command -v zed &>/dev/null || command -v zeditor &>/dev/null; then
  echo "  Setting up Zed theme integration..."
  
  # Create Zed themes directory
  mkdir -p ~/.config/zed/themes
  
  # Link current theme if it exists
  if [[ -f ~/.config/omarchy/current/theme/zed.json ]]; then
    ln -snf ~/.config/omarchy/current/theme/zed.json ~/.config/zed/themes/omarchy-current.json
    
    # Update Zed settings to use the theme
    ZED_SETTINGS="$HOME/.config/zed/settings.json"
    if [[ -f "$ZED_SETTINGS" ]]; then
      # Use Python to safely update the JSON
      python3 -c "
import json
import sys

settings_file = '$ZED_SETTINGS'
try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

# Update theme setting
settings['theme'] = 'Omarchy Current'

# Write back with nice formatting
with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null || true
    else
      # Create new settings.json with theme
      echo '{
  "theme": "Omarchy Current"
}' > "$ZED_SETTINGS"
    fi
    
    echo "  ✅ Zed theme integration complete"
  fi
else
  echo "  ℹ️  Zed not installed, skipping Zed theme setup"
fi

echo "✨ Zed editor theme support migration complete!"