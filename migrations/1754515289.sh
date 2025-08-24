echo "Update and restart Walker to resolve stuck Omarchy menu"

sudo pacman -Sy --noconfirm walker-bin
omarchy-restart-walker
