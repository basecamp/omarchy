echo "Replace Pi's Omarchy light/dark extension with the generated omarchy-system theme"

rm -f "$HOME/.pi/agent/extensions/omarchy-system-theme.ts"
omarchy-theme-refresh
omarchy-theme-set-pi --activate
