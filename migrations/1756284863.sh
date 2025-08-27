echo "Renaming waybar config file"

if [[ ! -f ~/.config/waybar/config.jsonc ]]; then
	mv ~/.config/waybar/config ~/.config/waybar/config.jsonc
fi
