echo "Install Impala as new wifi selection TUI"
yay -S --noconfirm --needed impala
gum confirm "Overwrite Waybar config to use Impala Wi-Fi selector in top bar?" && omarchy-refresh-waybar
