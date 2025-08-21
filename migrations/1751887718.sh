echo "Install Impala as new wifi selection TUI and bluetui for Bluetooth"
if ! command -v impala &>/dev/null; then
  yay -S --noconfirm --needed impala
fi

if ! command -v bluetui &>/dev/null; then
  yay -S --noconfirm --needed bluetui
fi

omarchy-refresh-waybar
