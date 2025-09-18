echo "Update and restart Walker to resolve stuck Omarchy menu"

sudo pacman -Syu --noconfirm --needed walker-bin
omarchy-restart-walker
