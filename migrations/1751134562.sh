echo "Ensure all indexes and packages are up to date"

omarchy-update-keyring
omarchy-refresh-pacman
sudo pacman -Syu --noconfirm
