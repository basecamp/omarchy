echo "Uniquely identify terminal apps with custom app-ids using omarchy-launch-tui"

sed -i 's/^\$terminal = uwsm-app -- xdg-terminal-exec$/$terminal = omarchy-launch-tui/' ~/.config/hypr/bindings.conf
sed -i 's/xdg-terminal-exec btop/omarchy-launch-tui btop/' ~/.config/waybar/config.jsonc
sed -i 's/\$terminal -e \([^ ]*\)/$terminal \1/g' ~/.config/hypr/bindings.conf

