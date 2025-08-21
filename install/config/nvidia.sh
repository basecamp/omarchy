#!/bin/bash

# ==============================================================================
# Hyprland NVIDIA Setup Script for Arch Linux
# ==============================================================================
# This script automates the installation and configuration of NVIDIA drivers
# for use with Hyprland on Arch Linux, following the official Hyprland wiki.
#
# Author: https://github.com/Kn0ax
#
# ==============================================================================

# --- GPU Detection ---
if [ -n "$(lspci | grep -i 'nvidia')" ]; then
  show_logo
  show_subtext "Install NVIDIA drivers..."

  # --- Driver Selection ---
  # Turing (16xx, 20xx), Ampere (30xx), Ada (40xx), and newer recommend the open-source kernel modules
  if echo "$(lspci | grep -i 'nvidia')" | grep -q -E "RTX [2-9][0-9]|GTX 16"; then
    NVIDIA_DRIVER_PACKAGE="nvidia-open-dkms"
  else
    NVIDIA_DRIVER_PACKAGE="nvidia-dkms"
  fi

  # Check which kernel is installed and set appropriate headers package
  KERNEL_HEADERS="linux-headers" # Default
  if pacman -Q linux-zen &>/dev/null; then
    KERNEL_HEADERS="linux-zen-headers"
  elif pacman -Q linux-lts &>/dev/null; then
    KERNEL_HEADERS="linux-lts-headers"
  elif pacman -Q linux-hardened &>/dev/null; then
    KERNEL_HEADERS="linux-hardened-headers"
  fi

  # Enable multilib repository for 32-bit libraries
  if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
  fi

  # force package database refresh
  sudo pacman -Syy

  # Install packages
  PACKAGES_TO_INSTALL=(
    "${KERNEL_HEADERS}"
    "${NVIDIA_DRIVER_PACKAGE}"
    "nvidia-utils"
    "lib32-nvidia-utils"
    "egl-wayland"
    "libva-nvidia-driver" # For VA-API hardware acceleration
    "qt5-wayland"
    "qt6-wayland"
  )

  yay -S --needed --noconfirm "${PACKAGES_TO_INSTALL[@]}"

  # Configure modprobe for early KMS
  echo "options nvidia_drm modeset=1" | sudo tee /etc/modprobe.d/nvidia.conf >/dev/null

  # Configure mkinitcpio for early loading
  MKINITCPIO_CONF="/etc/mkinitcpio.conf"

  # Define modules
  NVIDIA_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

  # Create backup
  sudo cp "$MKINITCPIO_CONF" "${MKINITCPIO_CONF}.backup"

  # Remove any old nvidia modules to prevent duplicates
  sudo sed -i -E 's/ nvidia_drm//g; s/ nvidia_uvm//g; s/ nvidia_modeset//g; s/ nvidia//g;' "$MKINITCPIO_CONF"
  # Add the new modules at the start of the MODULES array
  sudo sed -i -E "s/^(MODULES=\\()/\\1${NVIDIA_MODULES} /" "$MKINITCPIO_CONF"
  # Clean up potential double spaces
  sudo sed -i -E 's/  +/ /g' "$MKINITCPIO_CONF"

  sudo mkinitcpio -P

  # Add NVIDIA environment variables to envs.conf
  HYPRLAND_CONF="$HOME/default/hypr/envs.conf"
  if [ -f "$ENVS_CONF" ]; then
    cat >>"$ENVS_CONF" <<'EOF'

#----------------------nvidia-----------------------#
# This is from Hyprland Wiki. As a start, WLR_NO_HARDWARE_CURSORS 1 will be activated if nvidia gpu detected
#env = WLR_NO_HARDWARE_CURSORS,1
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
#env = GBM_BACKEND,nvidia-drm
 
#env = __NV_PRIME_RENDER_OFFLOAD,1
#env = __VK_LAYER_NV_optimus,NVIDIA_only
#env = WLR_DRM_NO_ATOMIC,1
env = NVD_BACKEND,direct
 
# FOR VM and POSSIBLY NVIDIA
# env = WLR_RENDERER_ALLOW_SOFTWARE,1
 
# nvidia firefox (for hardware acceleration on FF)?
# check this post https://github.com/elFarto/nvidia-vaapi-driver#configuration
# env = MOZ_DISABLE_RDD_SANDBOX,1
# env = NVD_BACKEND,direct
# env = EGL_PLATFORM,wayland
EOF
  fi
fi
