# Install all base packages
mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-base.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')

# Skip yaru-icon-theme if SKIP_YARU is set (for faster testing)
if [ -n "$SKIP_YARU" ]; then
  packages=($(printf '%s\n' "${packages[@]}" | grep -v '^yaru-icon-theme$'))
fi

# Use omarchy-aur-install for ARM (no omarchy mirror yet), pacman for x86
if [ -n "$OMARCHY_ARM" ]; then
  echo "Installing base packages using omarchy-aur-install (ARM)..."
  "$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" "${packages[@]}"
else
  omarchy-pkg-add "${packages[@]}"
fi
