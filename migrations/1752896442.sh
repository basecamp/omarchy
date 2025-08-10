echo "Replace volume control GUI with a TUI"

if ! command -v wiremix &>/dev/null; then
  yay -S --noconfirm --needed wiremix
  yay -Rns --noconfirm pavucontrol

  omarchy-refresh-applications
  omarchy-refresh-waybar
fi
