echo "Update Omarchy screensaver txt (if unchanged)"
if cmp -s $OMARCHY_PATH/logo.txt ~/.config/omarchy/branding/screensaver.txt; then
  cp "$OMARCHY_PATH/config/omarchy/branding/screensaver.txt" ~/.config/omarchy/branding/screensaver.txt
fi
