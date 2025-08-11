echo "Install Impala as new wifi selection TUI"
if ! command -v impala &>/dev/null; then
  yay -S --noconfirm --needed impala
  echo "You need to update the Waybar config to use Impala Wi-Fi selector in top bar."
  omarchy-refresh-waybar
fi
