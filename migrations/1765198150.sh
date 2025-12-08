echo "Display update version number and allow right-click to open release notes"

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"

if ! sed -n '/"custom\/update": {/,/},/p' "$WAYBAR_CONFIG" | grep -q '"on-click-right"'; then
  sed -i '/"custom\/update": {/,/},/ {
    /"exec":/a\    "on-click-right": "xdg-open https://github.com/basecamp/omarchy/releases",
  }' "$WAYBAR_CONFIG"
fi

UPDATE_BLOCK=$(sed -n '/"custom\/update": {/,/},/p' "$WAYBAR_CONFIG")

if ! grep -q '"tooltip-format"' <<<"$UPDATE_BLOCK"; then
  # Add if missing
  sed -i '/"custom\/update": {/,/},/ {
    /"exec":/a\    "tooltip-format": "{text}",
  }' "$WAYBAR_CONFIG"

elif grep -q '"tooltip-format": "Omarchy update available"' <<<"$UPDATE_BLOCK"; then
  # Replace if default
  sed -i '/"custom\/update": {/,/},/ {
    s/"tooltip-format": "Omarchy update available"/"tooltip-format": "{text}"/
  }' "$WAYBAR_CONFIG"
fi

omarchy-restart-waybar
