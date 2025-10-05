#!/bin/bash

# Architecture-specific package installation

# Check if running on ARM architecture
if [ -n "$OMARCHY_ARM" ]; then
  echo "Installing ARM-specific packages..."

  # Install any ARM-specific packages from the packages file using yay
  if [ -s "$OMARCHY_INSTALL/omarchy-arm.packages" ]; then
    mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-arm.packages" | grep -v '^$')
    if [ ${#packages[@]} -gt 0 ]; then
      yay -S --noconfirm --needed "${packages[@]}"
    fi
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

  source $OMARCHY_INSTALL/arm_install_scripts/obsidian-appimage.sh
  source $OMARCHY_INSTALL/arm_install_scripts/omarchy-lazyvim.sh

  # Skip Pinta if SKIP_PINTA is set (for faster testing)
  if [ -z "$SKIP_PINTA" ]; then
    source $OMARCHY_INSTALL/arm_install_scripts/pinta.sh
  fi

  source $OMARCHY_INSTALL/arm_install_scripts/walker-prebuilt.sh

  # Widevine is what allow for playing back DRM/protected content in browsers.
  # It's only available for ARM64 via the asahi-alarm repo. The
  # omarchy-chromium microfork includes a widevine hook for x86_64 and ARM64,
  # but this package is still necessary on ARM64 systems to provide the actual
  # widevine libraries. Without it, playback of DRM content (e.g. Netflix,
  # Disney+, Spotify, etc) will not work.
  echo "Detected ARM64 system - Installing widevine..."
  sudo pacman -S --needed --noconfirm asahi-alarm/widevine

  # Post-install tasks for ARM packages
  # Update icon cache for yaru-icon-theme (needed on ARM)
  if [ -d "/usr/share/icons/Yaru" ]; then
    echo "Updating Yaru icon cache for ARM..."
    sudo gtk-update-icon-cache /usr/share/icons/Yaru
  fi
else
  echo "Installing x86_64-specific packages..."

  # Install x86-specific packages using pacman with omarchy mirror
  mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-x86.packages" | grep -v '^$')
  if [ ${#packages[@]} -gt 0 ]; then
    sudo pacman -S --noconfirm --needed "${packages[@]}"
  fi
fi
