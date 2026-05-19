echo "Remove retired rounded-corners Hyprland toggle"

rm -f "$HOME/.local/state/omarchy/toggles/hypr/rounded-corners.lua"

if omarchy-cmd-present hyprctl; then
  hyprctl reload >/dev/null 2>&1 || true
fi
