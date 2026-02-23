echo "Switch back to mainline chromium now that it supports full live themeing"

if omarchy-pkg-present omarchy-chromium; then
  if gum confirm "Ready to switch to mainstream chromium? (Will close Chromium + reset settings)"; then
    pkill -x chromium
    omarchy-pkg-drop omarchy-chromium
    omarchy-pkg-add chromium
    omarchy-theme-set-browser
  fi
fi
