echo "Ensure all indexes and packages are up to date"

omarchy-refresh-pacman-mirrorlist
sudo pacman -Syu --noconfirm
