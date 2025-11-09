# ==============================================================================
# Hyprland NVIDIA Setup Script for Arch Linux
# ==============================================================================
# This script automates the installation and configuration of NVIDIA drivers
# for use with Hyprland on Arch Linux, following the official Hyprland wiki.
#
# Author: https://github.com/Kn0ax
#
# ==============================================================================

# Exit early if no nvidia devices found
if lspci | grep -qvi 'nvidia'; then
   exit 0
fi

# Driver Selection
NVIDIA_DRIVER_PACKAGE="nvidia-dkms"

# Turing (16xx, 20xx), Ampere (30xx), Ada (40xx), and newer recommend the open-source kernel modules
if lspci | grep -i 'nvidia' | grep -q -E "RTX [2-9][0-9]|GTX 16"; then
  NVIDIA_DRIVER_PACKAGE="nvidia-open-dkms"
fi

# Add headers to all supported kernels
KERNEL_HEADERS="$( pacman -Q | grep -E '^linux(-zen|-lts|-hardened)? ' |awk '{print $1 "-headers"}' )"

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
sudo pacman -Syu --needed --noconfirm "${PACKAGES_TO_INSTALL[@]}"

# Configure mkinitcpio for early loading
echo 'MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' | sudo tee /etc/mkinitcpio.conf.d/omarchy_nvidia.conf >/dev/null

# Regenerate initramfs with applied changes
sudo limine-mkinitcpio

# Add NVIDIA environment variables to envs.conf
HYPRLAND_CONF="$HOME/.config/hypr/envs.conf"
cat >>"$HYPRLAND_CONF" <<'EOF'

# NVIDIA environment variables
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
EOF
