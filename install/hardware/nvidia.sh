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

  # Per-session Hyprland NVIDIA env vars are handled by default/hypr/nvidia.lua.

  # Configure modprobe for early KMS
  mkdir -p /etc/modprobe.d
  cat > /etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=1
EOF

  # gpu-screen-recorder ships NVreg_PreserveVideoMemoryAllocations=1, so on
  # suspend the driver saves VRAM to /var/tmp over GSP RPCs. A
  # runtime-suspended GPU (the default on hybrid laptops) intermittently stops
  # answering those RPCs (Xid 119), wedging the suspend with the lid closed
  # (#5274). On s2idle systems the driver has a native path that sidesteps the
  # save entirely: S0ix power management keeps VRAM in self-refresh across
  # suspend while usage is below the driver's threshold (256 MB by default).
  if grep -q '\[s2idle\]' /sys/power/mem_sleep 2>/dev/null; then
    cat > /etc/modprobe.d/nvidia-s0ix.conf <<'EOF'
options nvidia NVreg_EnableS0ixPowerManagement=1
EOF

    # Record the machine-wide repair for migration 1787818004. Fresh installs
    # bake the option into the boot image built later in finalization, but a
    # user created after install starts with empty per-user migration state,
    # and without the marker their first login would redo the initramfs
    # rebuild for an option that is already in place.
    install -Dm644 /dev/null /var/lib/omarchy/migrations/1787818004
  fi

  # Configure mkinitcpio for early loading
  mkdir -p /etc/mkinitcpio.conf.d
  cat > /etc/mkinitcpio.conf.d/nvidia.conf <<'EOF'
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
fi
