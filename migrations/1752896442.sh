echo "Replace volume control GUI with a TUI"

if omarchy-cmd-missing wiremix; then
  omarchy-pkg-add wiremix
  omarchy-pkg-drop pavucontrol
  omarchy-refresh-applications
  omarchy-refresh-waybar
fi
