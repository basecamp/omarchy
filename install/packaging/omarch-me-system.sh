# Install all system packages
mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarch-me-system.packages" | grep -v '^$')
sudo pacman -S --noconfirm --needed "${packages[@]}"
