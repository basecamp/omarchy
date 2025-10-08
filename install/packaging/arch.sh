#!/bin/bash

# Architecture-specific package installation

# Check if running on ARM architecture
if [ -n "$OMARCHY_ARM" ]; then
  echo "Installing ARM-specific packages..."

  # Install any ARM-specific packages from the packages file
  if [ -s "$OMARCHY_INSTALL/omarchy-arm.packages" ]; then
    mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-arm.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')
    if [ ${#packages[@]} -gt 0 ]; then
      "$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" "${packages[@]}"
    fi
  fi

  # Install Asahi-specific packages if running on Asahi kernel (not VM)
  if uname -r | grep -qi "asahi"; then
    echo "Detected Asahi kernel - installing Asahi-specific packages..."
    if [ -s "$OMARCHY_INSTALL/omarchy-asahi.packages" ]; then
      mapfile -t asahi_packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-asahi.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')
      if [ ${#asahi_packages[@]} -gt 0 ]; then
        "$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" "${asahi_packages[@]}"
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

  source $OMARCHY_INSTALL/arm_install_scripts/obsidian-appimage.sh # Required fuse2 package included in omarchy-arm.packages
  source $OMARCHY_INSTALL/arm_install_scripts/omarchy-lazyvim.sh

  # Skip Pinta if SKIP_PINTA is set (for faster testing)
  if [ -z "$SKIP_PINTA" ]; then
    source $OMARCHY_INSTALL/arm_install_scripts/pinta.sh
  fi

  source $OMARCHY_INSTALL/arm_install_scripts/walker-prebuilt.sh

  # Post-install tasks for ARM packages
  # Update icon cache for yaru-icon-theme (needed on ARM)
  if [ -d "/usr/share/icons/Yaru" ]; then
    echo "Updating Yaru icon cache for ARM..."
    sudo gtk-update-icon-cache /usr/share/icons/Yaru
  fi
else
  echo "Installing x86_64-specific packages..."

  # Install x86-specific packages using pacman with omarchy mirror
  mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-x86.packages" | grep -v '^$' | sed 's/#.*$//' | sed 's/[[:space:]]*$//')
  if [ ${#packages[@]} -gt 0 ]; then
    sudo pacman -S --noconfirm --needed "${packages[@]}"
  fi
fi
