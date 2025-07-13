if [ -z "$OMARCHY_BARE" ]; then
  omarchy_xtras_packages=(
    gnome-calculator
    signal-desktop
    spotify
    dropbox-cli
    zoom
    obsidian-bin
    typora
    libreoffice
    obs-studio
    kdenlive
    1password-beta
    1password-cli
    gnome-keyring
    pinta
    xournalpp
    localsend-bin
  )

  # Initialize global array if it doesn't exist
  if [ -z "${omarchy_failed_packages+x}" ]; then
    omarchy_failed_packages=()
  fi

  for pkg in "${omarchy_xtras_packages[@]}"; do
    echo "Installing $pkg..."
    if ! yay -S --noconfirm --needed "$pkg"; then
      gum style --foreground 196 --bold "✗ Failed to install $pkg"
      omarchy_failed_packages+=("$pkg")
    fi
  done

  unset omarchy_xtras_packages
fi

# Copy over Omarchy applications
source ~/.local/share/omarchy/bin/omarchy-sync-applications || true