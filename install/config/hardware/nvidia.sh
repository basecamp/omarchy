OMARCHY_DESCRIPTION="NVIDIA GPU Configuration"

should_run() {
  NVIDIA_GPU=$(lspci | grep -i 'nvidia' || true)
  [[ -n "$NVIDIA_GPU" ]]
}

omarchy_install() {
  should_run || return 0

  # Turing (16xx, 20xx), Ampere (30xx), Ada (40xx), and newer recommend the open-source kernel modules
  if echo "$NVIDIA_GPU" | grep -q -E "RTX [2-9][0-9]|GTX 16"; then
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

  # force package database refresh
  sudo pacman -Syu --noconfirm

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

  sudo pacman -S --needed --noconfirm "${PACKAGES_TO_INSTALL[@]}"

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
  HYPRLAND_CONF="$HOME/.config/hypr/envs.conf"
  if [ -f "$HYPRLAND_CONF" ]; then
      cat >>"$HYPRLAND_CONF" <<'EOF'

# NVIDIA environment variables
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
EOF
  fi
}

omarchy_verify() {
  should_run || return 2

  pacman -Q nvidia-dkms &>/dev/null || pacman -Q nvidia-open-dkms &>/dev/null || add_error "NVIDIA driver not installed"

  [[ -f /etc/modprobe.d/nvidia.conf ]] || add_error "NVIDIA modprobe config missing"

  if [[ -f /etc/modprobe.d/nvidia.conf ]]; then
      grep -q "options nvidia_drm modeset=1" /etc/modprobe.d/nvidia.conf || add_error "NVIDIA DRM modeset not enabled"
  fi

  grep -q "nvidia" /etc/mkinitcpio.conf || add_error "NVIDIA modules not in mkinitcpio.conf"

  if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
      grep -q "LIBVA_DRIVER_NAME,nvidia" "$HOME/.config/hypr/hyprland.conf" || add_error "NVIDIA env vars not in Hyprland config"
  fi
}
