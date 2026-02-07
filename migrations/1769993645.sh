echo "Adding gum env config to hyprland.conf"
HYPRLAND_CONFIG=~/.config/hypr/hyprland.conf

if [[ -f $HYPRLAND_CONFIG ]]; then
	if ! grep -qx 'source = ~/.config/omarchy/current/theme/gum.env.conf' "$HYPRLAND_CONFIG"; then
		sed -i --follow-symlinks '/^source = ~\/\.config\/omarchy\/current\/theme\/hyprland\.conf$/a source = ~/.config/omarchy/current/theme/gum.env.conf' "$HYPRLAND_CONFIG"
	fi
    if ! grep -qx 'source = ~/.config/omarchy/current/theme/gum.env.conf' "$HYPRLAND_CONFIG"; then
    	echo "Error: Failed to add 'source = ~/.config/omarchy/current/theme/gum.env.conf' to $HYPRLAND_CONFIG."
    fi
fi

echo "Resetting theme"
omarchy-theme-reset
