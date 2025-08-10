echo "Update and restart Walker to resolve stuck Omarchy menu"

yay -Sy --noconfirm walker-bin
omarchy-state set restart-walker-required
