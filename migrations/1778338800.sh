echo "Enable Waybar weather tooltip"

   WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"

   if [[ -f $WAYBAR_CONFIG ]] && sed -n '/^  "custom\/weather": {$/,/^  },$/p' "$WAYBAR_CONFIG" | grep -q '"tooltip": false'; then
     sed -i '/^  "custom\/weather": {$/,/^  },$/ s/"tooltip": false/"tooltip": true/' "$WAYBAR_CONFIG"
     omarchy-restart-waybar
   fi
