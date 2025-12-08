echo "Display update version number and allow right-click to open release notes"

WAYBAR_CONFIG="$HOME/.config/waybar/config_test.jsonc"

# Check only inside custom/update for on-click-right
if ! sed -n '/"custom\/update": {/,/},/p' "$WAYBAR_CONFIG" | grep -q '"on-click-right"'; then
  sed -i '/"custom\/update": {/,/},/ {
    /"exec":/a\    "on-click-right": "xdg-open https://github.com/basecamp/omarchy/releases",
  }' "$WAYBAR_CONFIG"
fi

# Check only inside custom/update for tooltip-format
if ! sed -n '/"custom\/update": {/,/},/p' "$WAYBAR_CONFIG" | grep -q '"tooltip-format"'; then
  sed -i '/"custom\/update": {/,/},/ {
    /"exec":/a\    "tooltip-format": "{text}",
  }' "$WAYBAR_CONFIG"
fi

omarchy-restart-waybar
