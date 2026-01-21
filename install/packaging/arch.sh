#!/bin/bash

# Architecture-specific package installation

# Source common helpers
source "$OMARCHY_INSTALL/helpers/common.sh"

# Check if running on ARM architecture
if [ -n "$OMARCHY_ARM" ]; then
  echo "Installing ARM-specific packages..."

  # Install ARM-specific packages (split by source)

  # Official ARM packages first (use pacman directly to avoid yay's AUR scanning)
  if [ -s "$OMARCHY_INSTALL/omarchy-arm-official.packages" ]; then
    echo "Installing official ARM packages..."
    mapfile -t official_packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-arm-official.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')
    if [ ${#official_packages[@]} -gt 0 ]; then
      with_yes sudo pacman -S --noconfirm --needed "${official_packages[@]}"
    fi
  fi

  # AUR ARM packages second (with GitHub fallback)
  if [ -s "$OMARCHY_INSTALL/omarchy-arm-aur.packages" ]; then
    echo "Installing AUR ARM packages..."
    mapfile -t aur_packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-arm-aur.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')
    if [ ${#aur_packages[@]} -gt 0 ]; then
      "$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" "${aur_packages[@]}"
    fi
  fi

  # Install Asahi-specific packages if running on Asahi kernel (not VM)
  # Note: All Asahi packages are from official Asahi repos
  if uname -r | grep -qi "asahi"; then
    echo "Detected Asahi kernel - installing Asahi-specific packages..."
    if [ -s "$OMARCHY_INSTALL/omarchy-asahi.packages" ]; then
      mapfile -t asahi_packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-asahi.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')
      if [ ${#asahi_packages[@]} -gt 0 ]; then
        with_yes sudo pacman -S --noconfirm --needed "${asahi_packages[@]}"
      fi
    fi
  else
    echo "Skipping Asahi-specific packages (not running on Asahi kernel)"
  fi

  # Run ARM-specific installation scripts
  echo "Running ARM-specific installation scripts..."

  source $OMARCHY_INSTALL/arm_install_scripts/1password-app.sh
  source $OMARCHY_INSTALL/arm_install_scripts/1password-cli.sh
  source $OMARCHY_INSTALL/arm_install_scripts/asdcontrol-prebuilt.sh

  # Skip OBS Studio if SKIP_OBS is set (for faster testing)
  if [ -z "$SKIP_OBS" ]; then
    source $OMARCHY_INSTALL/arm_install_scripts/obs-studio.sh
  fi

  source $OMARCHY_INSTALL/arm_install_scripts/obsidian-appimage.sh # Required fuse2 package included in omarchy-arm-official.packages
  source $OMARCHY_INSTALL/arm_install_scripts/omarchy-nvim.sh
  source $OMARCHY_INSTALL/arm_install_scripts/tobi-try.sh
  source $OMARCHY_INSTALL/arm_install_scripts/walker-prebuilt.sh  # Prebuilt by default, set OMARCHY_BUILD_WALKER=true to build from source
  if [ -z "$SKIP_GHOSTTY" ]; then
    source $OMARCHY_INSTALL/arm_install_scripts/ghostty.sh
  fi

  # Skip Pinta if SKIP_PINTA is set (for faster testing)
  if [ -z "$SKIP_PINTA" ]; then
    source $OMARCHY_INSTALL/arm_install_scripts/pinta.sh
  fi

  # wl-clip-persist: ARM repos claim v0.5.0 (Sept 26 build) but mirrors still serve v0.4.3
  # Custom build required until ARM mirrors actually sync the new version
  source $OMARCHY_INSTALL/arm_install_scripts/wl-clip-persist.sh

  # Skip signal-desktop-beta if SKIP_SIGNAL_DESKTOP_BETA is set (for faster testing)
  if [ -z "$SKIP_SIGNAL_DESKTOP_BETA" ]; then
    # signal-desktop-beta: Requires nodejs-lts-jod which conflicts with current nodejs
    # Custom installer handles the conflict by removing nodejs before installation
    source $OMARCHY_INSTALL/arm_install_scripts/signal-desktop-beta.sh
  fi

  # Post-install tasks for ARM packages
  # Update icon cache for yaru-icon-theme (needed on ARM)
  # Use || true because gtk-update-icon-cache fails if index.theme is missing
  if [ -d "/usr/share/icons/Yaru" ]; then
    echo "Updating Yaru icon cache for ARM..."
    sudo gtk-update-icon-cache /usr/share/icons/Yaru || true
  fi
else
  echo "Installing x86_64-specific packages..."

  # Install x86-specific packages using pacman with omarchy mirror
  mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-x86.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')
  if [ ${#packages[@]} -gt 0 ]; then
    with_yes sudo pacman -S --noconfirm --needed "${packages[@]}"
  fi
fi
