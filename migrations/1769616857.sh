echo "Turn off opencode's own auto-update feature (we rely on pacman)"

# Note: We cannot use `jq` to update opencode.json because it’s JSONC (allows comments),
# which jq doesn’t support.

OPENCODE_SETTINGS="$HOME/.config/opencode/opencode.json"

# If opencode is installed, ensure that the "autoupdate" setting is set to false
if omarchy-cmd-present opencode; then
  mkdir -p "$(dirname "$OPENCODE_SETTINGS")"

  if [[ ! -f "$OPENCODE_SETTINGS" ]]; then
    cp $OMARCHY_PATH/config/opencode/opencode.json $OPENCODE_SETTINGS
  elif ! grep -q '"autoupdate"' "$OPENCODE_SETTINGS"; then
    # Insert "autoupdate": false, immediately after the first "{"
    # Use sed's first-match range (0,/{/) to only replace the first "{
    sed -i --follow-symlinks -E '0,/\{/{s/\{/{\
  "autoupdate": false,/}' "$OPENCODE_SETTINGS"
  fi
fi
