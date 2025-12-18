# Install all AUR packages
mapfile -t aurpackages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-aur.packages" | grep -v '^$')
yay -S --noconfirm --needed "${aurpackages[@]}"
