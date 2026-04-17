echo "Add flags sourcing to hyprland.conf"

HYPR_CONF=~/.config/hypr/hyprland.conf

source $OMARCHY_PATH/install/config/omarchy-config-flags.sh

if [[ -f $HYPR_CONF ]] && ! grep -q "flags/hypr/\*\.conf" "$HYPR_CONF"; then
  echo -e "\n# Toggle config flags dynamically\nsource = ~/.local/state/omarchy/flags/hypr/*.conf" >> "$HYPR_CONF"
fi
