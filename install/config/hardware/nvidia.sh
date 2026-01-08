NVIDIA="$(lspci | grep -i 'nvidia')"

if [ -n "$NVIDIA" ]; then
  # Check which kernel is installed and set appropriate headers package
  KERNEL_HEADERS="$(pacman -Qqs '^linux(-zen|-lts|-hardened)?$' | head -1)-headers"

  if echo "$NVIDIA" | grep -qE "RTX [2-9][0-9]|GTX 16"; then
    # Turing (16xx, 20xx), Ampere (30xx), Ada (40xx), and newer recommend the open-source kernel modules
    PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
  elif echo "$NVIDIA" | grep -qE "GTX 9|GTX 10|Quadro P"; then
    # Pascal (10xx or Quadro Pxxx) and Maxwell (9xx) use legacy branch that can only be installed from AUR
    PACKAGES=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
  fi
  # Bail if no supported GPU
  if [ -z "${PACKAGES+x}" ]; then
    echo "No compatible driver for your NVIDIA GPU. See: https://wiki.archlinux.org/title/NVIDIA"
    exit 0
  fi

  pacman -S --needed --noconfirm "$KERNEL_HEADERS" "${PACKAGES[@]}"

  # Configure modprobe for early KMS
  sudo tee /etc/modprobe.d/nvidia.conf <<EOF >/dev/null
options nvidia_drm modeset=1
EOF

  # Configure mkinitcpio for early loading
  sudo tee /etc/mkinitcpio.conf.d/nvidia.conf <<EOF >/dev/null
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF

  # Add NVIDIA environment variables
  cat >>$HOME/.config/hypr/envs.conf <<'EOF'

# NVIDIA
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
EOF
fi
