# Install base packages (split by source for reliability)

# Source common helpers
source "$OMARCHY_INSTALL/helpers/common.sh"

# Install official packages first (fast, reliable)
echo "Installing official base packages..."
mapfile -t official_packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-base-official.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')

if [ ${#official_packages[@]} -gt 0 ]; then
  if [ -n "$OMARCHY_ARM" ]; then
    # ARM: Use yay (handles official repos via pacman)
    yes_finite | yay -S --noconfirm --needed "${official_packages[@]}"
  else
    # x86: Use pacman directly (omarchy mirror)
    omarchy-pkg-add "${official_packages[@]}"
  fi
fi

# Install AUR packages second (with GitHub fallback)
echo "Installing AUR base packages..."
mapfile -t aur_packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-base-aur.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')

# Skip yaru-icon-theme if SKIP_YARU is set (for faster testing)
if [ -n "$SKIP_YARU" ]; then
  aur_packages=($(printf '%s\n' "${aur_packages[@]}" | grep -v '^yaru-icon-theme$'))
fi

if [ ${#aur_packages[@]} -gt 0 ]; then
  if [ -n "$OMARCHY_ARM" ]; then
    # ARM: Use omarchy-aur-install (AUR + GitHub fallback)
    "$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" "${aur_packages[@]}"
  else
    # x86: Use pacman (AUR packages pre-built in omarchy mirror)
    omarchy-pkg-add "${packages[@]}"
  fi
fi
