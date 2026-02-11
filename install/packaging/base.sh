# Install all base packages (--overwrite handles conflicts from omarchy-* custom packages)
mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-base.packages" | grep -v '^$')
sudo pacman -S --noconfirm --needed --overwrite '*' "${packages[@]}"
