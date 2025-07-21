echo "Add missing libappindicator-gtk3 for Dropbox icon tray to work right"

if ! pacman -Q libappindicator-gtk3 &>/dev/null; then
  yay -S --noconfirm --needed libappindicator-gtk3
fi
