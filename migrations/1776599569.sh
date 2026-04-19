#!/bin/bash
# Migration: Add Vibe Bar AI agents Waybar indicator

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_CSS="$HOME/.config/waybar/style.css"

echo "Adding Vibe Bar to Waybar configuration..."

# 1. Add module to modules-center (after custom/voxtype)
if [[ -f "$WAYBAR_CONFIG" ]] && ! grep -q '"custom/vibe-bar"' "$WAYBAR_CONFIG"; then
    sed -i 's/"custom\/voxtype"/"custom\/voxtype", "custom\/vibe-bar"/' "$WAYBAR_CONFIG"
    echo "  -> Added custom/vibe-bar to modules-center"
fi

# 2. Add module definition (before the tray block, like other migrations)
if [[ -f "$WAYBAR_CONFIG" ]] && ! grep -q '"custom/vibe-bar":' "$WAYBAR_CONFIG"; then
    sed -i '/"tray": {/i\  "custom\/vibe-bar": {\n    "exec": "$OMARCHY_PATH\/default\/vibe-bar\/waybar_status.sh",\n    "return-type": "json",\n    "interval": 1,\n    "signal": 11,\n    "on-click": "omarchy-vibe-bar panel",\n    "tooltip": true\n  },' "$WAYBAR_CONFIG"
    echo "  -> Added module definition"
fi

# 3. Add CSS (append if not present)
if [[ -f "$WAYBAR_CSS" ]] && ! grep -q "#custom-vibe-bar" "$WAYBAR_CSS"; then
    cat >> "$WAYBAR_CSS" << 'CSS_EOF'

/* Vibe Bar styling */
#custom-vibe-bar {
  min-width: 12px;
  margin: 0 7.5px;
  font-size: 12px;
}

#custom-vibe-bar.agents-idle {
  opacity: 0.4;
}

#custom-vibe-bar.agents-active {
  color: @foreground;
}

#custom-vibe-bar.agents-waiting {
  color: #f9a825;
  animation: vibe-bar-pulse 1.2s ease-in-out infinite;
}

@keyframes vibe-bar-pulse {
  0% { opacity: 1; }
  50% { opacity: 0.4; }
  100% { opacity: 1; }
}
CSS_EOF
    echo "  -> Added CSS styling"
fi

# 4. Install service, hooks, and OpenCode plugin
bash "$OMARCHY_PATH/install/config/vibe-bar.sh"

echo "Restarting omarchy-vibe-bar service..."
systemctl --user restart omarchy-vibe-bar

echo "Restarting Waybar..."
omarchy-restart-waybar
