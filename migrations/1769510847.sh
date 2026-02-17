echo "Switch back to mainline chromium now that it supports full live themeing"
echo "Note: This required resetting cookies and settings!"

omarchy-pkg-drop omarchy-chromium
omarchy-pkg-add chromium
omarchy-theme-set-browser
