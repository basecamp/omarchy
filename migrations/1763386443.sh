echo "Uniquely identify terminal apps with custom app-ids"

sed -i 's/\$terminal -e btop/$terminal --app-id=com.omarchy.btop -e btop/' ~/.config/hypr/bindings.conf
sed -i 's/xdg-terminal-exec btop/xdg-terminal-exec --app-id=com.omarchy.btop btop/' ~/.config/waybar/config.jsonc
sed -i 's/\$terminal -e lazydocker/$terminal --app-id=com.omarchy.lazydocker -e lazydocker/' ~/.config/hypr/bindings.conf
