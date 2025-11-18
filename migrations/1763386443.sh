echo "Uniquely identify terminal apps with custom app-ids using omarchy-launch-tui"

# Update terminal variable in bindings.conf
sed -i 's/^\$terminal = uwsm-app -- xdg-terminal-exec$/$terminal = omarchy-launch-tui/' ~/.config/hypr/bindings.conf

# Remove -e flag from terminal commands
sed -i 's/\$terminal -e \([^ ]*\)/$terminal \1/g' ~/.config/hypr/bindings.conf

# Update waybar to use omarchy-launch-or-focus for TUI apps
sed -i 's/xdg-terminal-exec btop/omarchy-launch-or-focus com.omarchy.btop omarchy-launch-tui btop/' ~/.config/waybar/config.jsonc
sed -i 's/xdg-terminal-exec --app-id=com\.omarchy\.Wiremix -e wiremix/omarchy-launch-or-focus com.omarchy.wiremix omarchy-launch-tui wiremix/' ~/.config/waybar/config.jsonc
