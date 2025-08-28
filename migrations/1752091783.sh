echo "Install Plymouth splash screen"

sudo pacman -S --needed --noconfirm uwsm plymouth
source "$HOME/.local/share/omarchy/install/login/plymouth.sh"
