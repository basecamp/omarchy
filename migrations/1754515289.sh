echo "Update and restart Walker to resolve stuck Omarchy menu"

yay -Sy --noconfirm walker-bin
~/.local/share/omarchy/bin/omarchy-restart-walker
