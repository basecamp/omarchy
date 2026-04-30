echo "Update Waybar screen recording command"

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"

if [[ -f $WAYBAR_CONFIG ]] && grep -q 'omarchy-cmd-screenrecord' "$WAYBAR_CONFIG"; then
  sed -i 's/omarchy-cmd-screenrecord/omarchy-capture-screenrecording/g' "$WAYBAR_CONFIG"
  omarchy-restart-waybar
fi
