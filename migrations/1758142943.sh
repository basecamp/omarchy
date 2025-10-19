echo "Turn off VSCode's own auto-update feature (we rely on pacman)"

# Note: We cannot use `jq` to update settings.json because it’s JSONC (allows comments),
# which jq doesn’t support.

VS_CODE_SETTINGS="$HOME/.config/Code/User/settings.json"

# If VSCode is installed, ensure that the "update.mode" setting is set to "none"
if omarchy-cmd-present code; then
  mkdir -p "$(dirname "$VS_CODE_SETTINGS")"

  if [[ ! -f "$VS_CODE_SETTINGS" ]]; then
    # If settings.json doesn't exist, create it with just the update.mode setting
    printf '{\n  "update.mode": "none"\n}\n' > "$VS_CODE_SETTINGS"
 elif ! grep -q '"update.mode"' "$VS_CODE_SETTINGS"; then
    # Insert "update.mode": "none", immediately after the first "{"
    # Use sed's first-match range (0,/{/) to only replace the first "{
    sed -i --follow-symlinks -E '0,/\{/{s/\{/{\
  "update.mode": "none",/}' "$VS_CODE_SETTINGS"
  fi
fi
