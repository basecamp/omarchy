#!/bin/bash

echo "Add timer to Waybar"

patch -N ~/.config/waybar/config.jsonc << 'EOF'
--- a/waybar/config.jsonc
+++ b/waybar/config.jsonc
@@ -5,7 +5,7 @@
   "spacing": 0,
   "height": 26,
   "modules-left": ["custom/omarchy", "hyprland/workspaces"],
-  "modules-center": ["clock", "custom/update", "custom/voxtype", "custom/screenrecording-indicator"],
+  "modules-center": ["custom/timer", "clock", "custom/update", "custom/voxtype", "custom/screenrecording-indicator"],
   "modules-right": [
     "group/tray-expander",
     "bluetooth",
@@ -142,6 +142,14 @@
     "signal": 8,
     "return-type": "json"
   },
+  "custom/timer": {
+      "exec": "$OMARCHY_PATH/default/waybar/indicators/timer.sh",
+      "return-type": "json",
+      "on-click-right": "rm -f $XDG_RUNTIME_DIR/omarchy-active-timer",
+      "format": "{text}",
+      "format-alt": "{alt}",
+      "hide-empty-text": true
+  },
   "custom/voxtype": {
     "exec": "omarchy-voxtype-status",
     "return-type": "json",
EOF

omarchy-restart-hyprctl
omarchy-restart-waybar
