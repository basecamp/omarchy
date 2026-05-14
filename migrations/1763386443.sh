echo "Uniquely identify terminal apps with custom app-ids using omarchy-launch-tui"

# Replace terminal -e calls with omarchy-launch-tui in bindings
sed -i 's/\$terminal -e \([^ ]*\)/omarchy-launch-tui \1/g' ~/.config/hypr/bindings.conf
