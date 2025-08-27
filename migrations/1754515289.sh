echo "Update and restart Walker to resolve stuck Omarchy menu"

sudo pacman -Syu --noconfirm walker-bin
omarchy-restart-walker
