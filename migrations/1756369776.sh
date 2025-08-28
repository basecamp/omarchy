echo "Move to the new woff2 format for Font Awesome 7.0"

sudo pacman -S --noconfirm --needed woff2-font-awesome
sudo pacman -Rns --noconfirm ttf-font-awesome || true
