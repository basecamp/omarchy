# Install all base packages
# Use lite or full package list based on edition
if [[ "${OMARCHY_EDITION:-full}" == "lite" ]]; then
  package_file="$OMARCHY_INSTALL/omarchy-base-lite.packages"
else
  package_file="$OMARCHY_INSTALL/omarchy-base.packages"
fi

mapfile -t packages < <(grep -v '^#' "$package_file" | grep -v '^$')
sudo pacman -S --noconfirm --needed "${packages[@]}"
