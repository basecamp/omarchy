echo "Convert Hyprland rounded corners toggle to Lua"

old_toggle="$HOME/.local/state/omarchy/toggles/hypr/rounded-corners.conf"
new_toggle="$HOME/.local/state/omarchy/toggles/hypr/rounded-corners.lua"

if [[ -f $old_toggle ]]; then
  mkdir -p "$(dirname "$new_toggle")"
  cp "$OMARCHY_PATH/default/hypr/toggles/rounded-corners.lua" "$new_toggle"
  rm -f "$old_toggle"
  hyprctl reload >/dev/null 2>&1 || true
fi
