echo "Add background cycling feature"

# Cleanup obsolete files from previous modular approach if they exist
rm -f ~/.local/share/omarchy/bin/omarchy-bg-cycle-daemon \
      ~/.local/share/omarchy/bin/omarchy-toggle-bg-cycle \
      ~/.local/share/omarchy/bin/omarchy-set-bg-cycle-interval

AUTOSTART_FILE="$HOME/.config/hypr/autostart.conf"

if [ -f "$AUTOSTART_FILE" ]; then
  # Remove the temporary extension version if it exists
  sed -i '/omarchy\/extensions\/omarchy-bg-cycle-daemon/d' "$AUTOSTART_FILE"
  
  # Update daemon name if user had the old modular version
  sed -i 's/omarchy-bg-cycle-daemon/omarchy-bg-cycle/g' "$AUTOSTART_FILE"

  # Add the core version if not already present
  if ! grep -q "omarchy-bg-cycle" "$AUTOSTART_FILE"; then
    sed -i '/exec-once = uwsm-app -- swayosd-server/a exec-once = [ -f "$HOME/.local/state/omarchy/bg-cycle-active" ] && omarchy-bg-cycle' "$AUTOSTART_FILE"
  fi
fi