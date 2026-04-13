echo "Set Chromium appearance mode to device (follow system) by default"

echo '{"browser":{"theme":{"color_scheme":0}}}' | sudo tee /usr/lib/chromium/initial_preferences >/dev/null

# Update existing Chromium profiles to use "device" instead of "dark"
PREFS="$HOME/.config/chromium/Default/Preferences"
if [[ -f "$PREFS" ]] && command -v jq &>/dev/null; then
  jq '.browser.theme.color_scheme = 0' "$PREFS" > "$PREFS.tmp" && mv "$PREFS.tmp" "$PREFS"
fi
