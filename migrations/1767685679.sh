echo "Add voxtype to waybar"

patch -N ~/.config/waybar/style.css << 'EOF'
--- a/waybar/style.css
+++ b/waybar/style.css
@@ -74,10 +74,16 @@ tooltip {

 #custom-screenrecording-indicator {
   min-width: 12px;
-  margin-left: 8.75px;
+  margin-left: 5px;
   font-size: 10px;
+  padding-bottom: 1px;
 }

 #custom-screenrecording-indicator.active {
   color: #a55555;
 }
+
+#custom-voxtype {
+  min-width: 12px;
+  margin: 0 0 0 7.5px;
+}
EOF

patch -N ~/.config/waybar/config.jsonc << 'EOF'
--- a/waybar/config.jsonc
+++ b/waybar/config.jsonc
@@ -5,7 +5,7 @@
   "spacing": 0,
   "height": 26,
   "modules-left": ["custom/omarchy", "hyprland/workspaces"],
-  "modules-center": ["clock", "custom/update", "custom/screenrecording-indicator"],
+  "modules-center": ["clock", "custom/update", "custom/voxtype", "custom/screenrecording-indicator"],
   "modules-right": [
     "group/tray-expander",
     "bluetooth",
@@ -140,6 +140,19 @@
     "signal": 8,
     "return-type": "json"
   },
+  "custom/voxtype": {
+    "exec": "omarchy-voxtype-status",
+    "return-type": "json",
+    "format": "{icon}",
+    "format-icons": {
+      "idle": "",
+      "recording": "󰍬",
+      "transcribing": "󰔟"
+    },
+    "tooltip": true,
+    "on-click-right": "omarchy-voxtype-config",
+    "on-click": "omarchy-voxtype-model"
+  },
   "tray": {
     "icon-size": 12,
     "spacing": 17
EOF

omarchy-restart-waybar
