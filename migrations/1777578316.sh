echo "Rename screen recording command"

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"

if [[ -f $WAYBAR_CONFIG ]] && grep -q 'omarchy-capture-screencording' "$WAYBAR_CONFIG"; then
  sed -i 's/omarchy-capture-screencording/omarchy-capture-screenrecording/g' "$WAYBAR_CONFIG"
  omarchy-restart-waybar
fi
