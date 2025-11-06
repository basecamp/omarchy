echo "Install bluetui as new bluetooth selection TUI"

if omarchy-cmd-missing bluetui; then
  omarchy-pkg-add bluetui
  omarchy-refresh-waybar
fi