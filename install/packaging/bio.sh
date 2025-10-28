# Install optional biological software packages
# First ensure Python and R are installed via Omarchy dev environment

echo "Ensuring Python dev environment is installed..."
if ! command -v uv &> /dev/null; then
  omarchy-install-dev-env python
fi

echo "Ensuring R is installed..."
if ! command -v R &> /dev/null; then
  omarchy-install-dev-env r
fi

# Install system packages via yay (handles both AUR and official repos)
echo "Installing biological software packages..."
mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-bio.packages" | grep -v '^$')
yay -S --noconfirm --needed "${packages[@]}"
