if lspci | grep -qi 'nvidia'; then
  # Check which kernel is installed and set appropriate headers package
  KERNEL_PACKAGE=$(pacman -Qqs '^linux(-zen|-lts|-hardened|-t2|-ptl)?$' | head -1 || true)
  [[ -n $KERNEL_PACKAGE ]] && omarchy-pkg-add "$KERNEL_PACKAGE-headers"

  if omarchy-hw-nvidia-gsp; then
    PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
  elif omarchy-hw-nvidia-without-gsp; then
    PACKAGES=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
  fi

  # Bail if no supported GPU
  if [[ -z ${PACKAGES+x} ]]; then
    echo "No compatible driver for your NVIDIA GPU. See: https://wiki.archlinux.org/title/NVIDIA"
    exit 0
  fi

  omarchy-pkg-add "${PACKAGES[@]}"

  # gpu-screen-recorder (base package set) ships a modprobe drop-in setting
  # NVreg_PreserveVideoMemoryAllocations=1. The 580xx driver has no kernel
  # suspend notifier support, so with that option it depends on these services
  # to save and restore VRAM around sleep; without them resume returns to
  # corrupted GPU state. The open modules need none of this: they handle it
  # automatically via NVreg_UseKernelSuspendNotifiers=1 from nvidia-utils'
  # own nvidia-sleep.conf.
  if omarchy-hw-nvidia-without-gsp; then
    systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
  fi

  # Per-session Hyprland NVIDIA env vars are handled by default/hypr/nvidia.lua.

  # Configure modprobe for early KMS
  mkdir -p /etc/modprobe.d
  cat > /etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=1
EOF

  # Configure mkinitcpio for early loading
  mkdir -p /etc/mkinitcpio.conf.d
  cat > /etc/mkinitcpio.conf.d/nvidia.conf <<'EOF'
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
fi
