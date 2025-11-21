echo "Move Omarchy Package Repository after Arch core/extra/multilib and remove AUR"

omarchy-refresh-pacman
sudo pacman -Syu --noconfirm
