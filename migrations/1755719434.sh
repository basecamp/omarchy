echo "Add direct-to-clipboard screenshot keybinding (SUPER+SHIFT+PRINT)"

# Update the screenshot script to support clipboard mode
SCREENSHOT_SCRIPT="$HOME/.local/share/omarchy/bin/omarchy-cmd-screenshot"

if [ -f "$SCREENSHOT_SCRIPT" ] && ! grep -q '"clipboard"' "$SCREENSHOT_SCRIPT"; then
  # Add clipboard mode handling after the MODE line
  sed -i '/^MODE="${1:-region}"/a\
\
# Direct to clipboard mode\
if [[ "$MODE" == "clipboard" ]]; then\
  pkill slurp || hyprshot -m region --raw | wl-copy\
  notify-send "Screenshot copied" "Screenshot copied to clipboard" -t 2000\
  exit 0\
fi' "$SCREENSHOT_SCRIPT"
  
  echo "Updated screenshot script with clipboard mode"
fi

# Add keybinding to default config
DEFAULT_UTILITIES_CONF="$HOME/.local/share/omarchy/default/hypr/bindings/utilities.conf"

if [ -f "$DEFAULT_UTILITIES_CONF" ] && ! grep -q "Screenshot to clipboard" "$DEFAULT_UTILITIES_CONF"; then
  # Add the new keybinding after the existing screenshot bindings
  sed -i '/bindd = CTRL, PRINT, Screenshot of display/a\
\
# Screenshot direct to clipboard (no Satty)\
bindd = SUPER SHIFT, PRINT, Screenshot to clipboard, exec, omarchy-cmd-screenshot clipboard' "$DEFAULT_UTILITIES_CONF"
  
  echo "Added direct-to-clipboard screenshot keybinding"
fi

# Reload Hyprland if running
if pgrep -x Hyprland >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
  echo "Hyprland configuration reloaded"
fi