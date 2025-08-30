echo "Replace volume control GUI with a TUI"

if cmd-missing wiremix; then
  pkg-add wiremix
  pkg-remove pavucontrol
  omarchy-refresh-applications
  omarchy-refresh-waybar
fi
