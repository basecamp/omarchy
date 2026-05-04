echo "Uniquely identify terminal apps with custom app-ids using omarchy-launch-tui"

# Replace terminal -e calls with omarchy-launch-tui in bindings
sed -i 's/\$terminal -e \([^ ]*\)/omarchy-launch-tui \1/g' ~/.config/hypr/bindings.conf

# Update waybar to use omarchy-launch-or-focus with omarchy-launch-tui for TUI apps
sed -i 's|xdg-terminal-exec btop|omarchy-launch-or-focus-tui btop|' ~/.config/waybar/config.jsonc
sed -i 's|xdg-terminal-exec --app-id=com\.omarchy\.Wiremix -e wiremix|omarchy-launch-or-focus-tui wiremix|' ~/.config/waybar/config.jsonc
