echo "Add background cycling feature"

AUTOSTART_FILE="$HOME/.config/hypr/autostart.conf"

if [ -f "$AUTOSTART_FILE" ]; then
  # Remove the temporary extension version if it exists
  sed -i '/omarchy\/extensions\/omarchy-bg-cycle-daemon/d' "$AUTOSTART_FILE"
  
  # Add the core version if not already present
  if ! grep -q "omarchy-bg-cycle-daemon" "$AUTOSTART_FILE"; then
    sed -i '/exec-once = uwsm-app -- swayosd-server/a exec-once = [ -f "$HOME/.local/state/omarchy/bg-cycle-active" ] && omarchy-bg-cycle-daemon' "$AUTOSTART_FILE"
  fi
fi
