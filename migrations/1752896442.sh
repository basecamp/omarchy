echo "Replace volume control GUI with a TUI"

if ! command -v wiremix &>/dev/null; then
  yay -S --noconfirm --needed wiremix
  yay -Rns --noconfirm pavucontrol

  ~/.local/share/omarchy/bin/omarchy-refresh-applications
  ~/.local/share/omarchy/bin/omarchy-refresh-waybar
fi
