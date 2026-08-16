echo "Remove the obsolete Voxtype Hyprland toggle"

rm -f "$HOME/.local/state/omarchy/toggles/hypr/voxtype.lua"

# The Quattro upgrade runs the packaged migrations against a still-running
# Omarchy 3 session whose config is mid-swap, so a reload here only re-parses a
# config that cannot resolve yet. That paints an error bar Hyprland then keeps
# up until something reloads cleanly, which the upgrade deliberately never does.
# Nothing is reading this toggle in that session anyway; the reboot applies it.
if [[ ${OMARCHY_UPGRADE_TO_QUATTRO_LIVE:-0} != "1" ]]; then
  hyprctl reload >/dev/null 2>&1 || true
fi
