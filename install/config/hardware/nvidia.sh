set -euo pipefail
NVIDIA="$(lspci | grep -i 'nvidia' || true)"
if [ -n "$NVIDIA" ]; then
  echo "Detected NVIDIA GPU(s):"
  echo "$NVIDIA"
  echo
  # Check which kernel is installed and set appropriate headers package
  mapfile -t KERNEL_HEADERS < <(
    pacman -Qqe \
      | grep -E '^linux(-zen|-lts|-hardened)?$' \
      | sed 's/$/-headers/'
  )
  if [ "${#KERNEL_HEADERS[@]}" -eq 0 ]; then
    echo "No omarchy supported kernels found (linux, linux-zen, linux-lts, linux-hardened). Aborting."
    exit 1
  fi
  if echo "$NVIDIA" | grep -qE "RTX [2-9][0-9]|GTX 16"; then
    # Turing (16xx, 20xx), Ampere (30xx), Ada (40xx), and newer recommend the open-source kernel modules
    PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
  elif echo "$NVIDIA" | grep -qE "GTX 9|GTX 10|Quadro P"; then
    # Pascal (10xx or Quadro Pxxx) and Maxwell (9xx) use legacy branch that can only be installed from AUR
    PACKAGES=(omarchy/nvidia-580xx-dkms omarchy/nvidia-580xx-utils omarchy/lib32-nvidia-580xx-utils)
  fi
  # Bail if no supported GPU
  if [ -z "${PACKAGES+x}" ]; then
    echo "No compatible driver for your NVIDIA GPU. See: https://wiki.archlinux.org/title/NVIDIA"
    exit 0
  fi

  echo "Reinstalling kernel headers for: ${KERNEL_HEADERS[*]}"
  sudo pacman -S --noconfirm "${KERNEL_HEADERS[@]}"

  echo "Installing / updating NVIDIA packages: ${PACKAGES[*]}"
  # use omarchy helper for drivers (expands args, not the array name)
  omarchy-pkg-add "${PACKAGES[@]}"

  # Explicitly rebuild DKMS
  if command -v dkms > /dev/null 2>&1; then
    if ! sudo dkms autoinstall --force; then
      sudo dkms autoinstall --force
    fi
    sudo depmod -a || true
  fi
  # Configure modprobe for early KMS
  sudo tee /etc/modprobe.d/nvidia.conf << EOF > /dev/null
options nvidia_drm modeset=1
EOF
  # Configure mkinitcpio for early loading
  sudo tee /etc/mkinitcpio.conf.d/nvidia.conf << EOF > /dev/null
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
  # Rebuild initramfs
  if command -v mkinitcpio > /dev/null 2>&1; then
    if ! sudo mkinitcpio -P; then
      sudo mkinitcpio -P
    fi
  else
    echo "mkinitcpio not found; skipping initramfs rebuild."
  fi
  # Add NVIDIA environment variables
  cat >> "${HOME}"/.config/hypr/envs.conf << 'EOF'

# NVIDIA
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
EOF

fi
