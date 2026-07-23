echo "Remove the obsolete Voxtype Hyprland toggle"

rm -f "$HOME/.local/state/omarchy/toggles/hypr/voxtype.lua"
hyprctl reload >/dev/null 2>&1 || true
