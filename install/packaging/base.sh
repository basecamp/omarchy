# Install all base packages
mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-base.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')

# Skip yaru-icon-theme if SKIP_YARU is set (for faster testing)
if [ -n "$SKIP_YARU" ]; then
  packages=($(printf '%s\n' "${packages[@]}" | grep -v '^yaru-icon-theme$'))
fi

# Use yay for ARM (no omarchy mirror yet), pacman for x86
if [ -n "$OMARCHY_ARM" ]; then
  echo "Installing base packages using yay (ARM)..."
  yay -S --noconfirm --needed "${packages[@]}"
else
  omarchy-pkg-add "${packages[@]}"
fi
