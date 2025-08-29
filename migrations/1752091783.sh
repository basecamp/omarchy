echo "Install Plymouth splash screen"

sudo pacman -S --needed --noconfirm uwsm plymouth
source "$OMARCHY_PATH/install/login/plymouth.sh"
