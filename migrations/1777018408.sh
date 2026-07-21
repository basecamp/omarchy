echo "Fix Chromium appearance mode to also set color_scheme2 (the field Chromium actually reads now)"

echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' | sudo tee /usr/lib/chromium/initial_preferences >/dev/null

# Update existing Chromium profiles so color_scheme2 follows the system, not dark
PREFS="$HOME/.config/chromium/Default/Preferences"
if [[ -f "$PREFS" ]] && command -v jq &>/dev/null; then
  jq '.browser.theme.color_scheme = 0 | .browser.theme.color_scheme2 = 0' "$PREFS" > "$PREFS.tmp" && mv "$PREFS.tmp" "$PREFS"
fi
