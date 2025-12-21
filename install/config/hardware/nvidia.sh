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
  # --- Driver Selection ---
  NVIDIA_DRIVER_CURRENT="current"
  NVIDIA_DRIVER_LEGACY="legacy"
  if echo "$(lspci | grep -i 'nvidia')" | grep -q -E "RTX [2-9][0-9]|GTX 16"; then
    NVIDIA_DRIVER="$NVIDIA_DRIVER_CURRENT"
  else
    NVIDIA_DRIVER="$NVIDIA_DRIVER_LEGACY"
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

  # force package database refresh
  sudo pacman -Syu --noconfirm

  # Initial install packages
  GENERAL_PACKAGES=(
    "${KERNEL_HEADERS}"
    "egl-wayland"
    "qt5-wayland"
    "qt6-wayland"
  )

  # Turing (16xx, 20xx), Ampere (30xx), Ada (40xx), and newer recommend the open-source kernel modules
  # Pascal (10xx), Maxwell (9xx), Kepler (7xx) and older use legacy branch that can only be installed from AUR
  if [ "$NVIDIA_DRIVER" = "$NVIDIA_DRIVER_CURRENT" ]; then
    DRIVER_PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
    sudo pacman -S --needed --noconfirm "${GENERAL_PACKAGES[@]}" "${DRIVER_PACKAGES[@]}"
  elif [ "$NVIDIA_DRIVER" = "$NVIDIA_DRIVER_LEGACY" ]; then
    sudo pacman -S --needed --noconfirm "${GENERAL_PACKAGES[@]}"
    if ! command -v yay &>/dev/null; then
      echo "ERROR: Older NVIDIA GPUs require nvidia-580xx-dkms from AUR."
      echo "Please install yay."
      exit 1
    fi
    LEGACY_DRIVER_PACKAGES=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
    yay -S --needed --noconfirm "${LEGACY_DRIVER_PACKAGES[@]}"
  fi

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

  # Add NVIDIA environment variables to hyprland.conf
  HYPRLAND_CONF="$HOME/.config/hypr/hyprland.conf"
  if [ -f "$HYPRLAND_CONF" ]; then
    cat >>"$HYPRLAND_CONF" <<'EOF'

# NVIDIA environment variables
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
EOF
  fi
fi
