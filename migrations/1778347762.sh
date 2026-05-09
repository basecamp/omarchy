echo "Replace Pi's Omarchy light/dark extension with the generated omarchy-system theme"

rm -f ~/.pi/agent/extensions/omarchy-system-theme.ts
"$OMARCHY_PATH/bin/omarchy-theme-set-pi" --activate
