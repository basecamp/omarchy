echo "Replace blueberry with bluetui"

if omarchy-cmd-missing Bluetui; then
  omarchy-pkg-add bluetui
fi

if omarchy-pkg-present blueberry; then
  omarchy-pkg-drop blueberry
fi

omarchy-refresh-waybar
