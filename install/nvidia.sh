# ==============================================================================
# Hyprland NVIDIA Setup Script for Fedora Linux
# ==============================================================================
# This script automates the installation and configuration of NVIDIA drivers
# for use with Hyprland on Fedora Linux.
#
# Author: https://github.com/Kn0ax (adapted for Fedora)
#
# ==============================================================================

# --- GPU Detection ---
if [ -n "$(lspci | grep -i 'nvidia')" ]; then
  # --- Driver Selection ---
  # On Fedora, use the RPMFusion repositories for NVIDIA drivers
  # Enable RPMFusion repositories if not already enabled
  sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
  sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

  # Install NVIDIA drivers
  PACKAGES_TO_INSTALL=(
    "akmod-nvidia"             # NVIDIA driver with DKMS-like functionality
    "xorg-x11-drv-nvidia-cuda" # CUDA support
    "nvidia-vaapi-driver"      # For VA-API hardware acceleration
    "libva-nvidia-driver"
    "qt5-qtwayland"
    "qt6-qtwayland"
  )

  sudo dnf install -y "${PACKAGES_TO_INSTALL[@]}"

  # Configure modprobe for early KMS
  echo "options nvidia_drm modeset=1" | sudo tee /etc/modprobe.d/nvidia.conf >/dev/null

  # On Fedora, dracut is used instead of mkinitcpio
  # Configure dracut for early loading
  echo 'add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | sudo tee /etc/dracut.conf.d/nvidia.conf >/dev/null

  sudo dracut --force

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
