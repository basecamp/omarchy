echo "Install Impala as new wifi selection TUI"
if ! command -v impala &>/dev/null; then
  yay -S --noconfirm --needed impala
  gum confirm "Overwrite Waybar config to use Impala Wi-Fi selector in top bar?" && omarchy-refresh-waybar
fi
