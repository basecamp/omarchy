echo "Ensure all indexes and packages are up to date"

omarchy-refresh-pacman
sudo pacman -Syu --noconfirm
