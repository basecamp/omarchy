echo "Uniquely identify btop with custom app-id"

sed -i 's/\$terminal -e btop/$terminal --app-id=com.omarchy.btop -e btop/' ~/.config/hypr/bindings.conf
sed -i 's/xdg-terminal-exec btop/xdg-terminal-exec --app-id=com.omarchy.btop btop/' ~/.config/waybar/config.jsonc
