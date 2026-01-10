echo "Add NVIDIA suspend/resume video memory preservation"

# Only apply to systems with NVIDIA GPU
NVIDIA="$(lspci | grep -i 'nvidia')"
if [ -z "$NVIDIA" ]; then
  exit 0
fi

NVIDIA_CONF="/etc/modprobe.d/nvidia.conf"

# Check if the config already has the preserve setting
if [ -f "$NVIDIA_CONF" ] && grep -q "NVreg_PreserveVideoMemoryAllocations=1" "$NVIDIA_CONF"; then
  echo "NVIDIA video memory preservation already configured"
  exit 0
fi

# Add or update the nvidia.conf file
sudo tee "$NVIDIA_CONF" <<EOF >/dev/null
options nvidia_drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

echo "Regenerating initramfs..."
if omarchy-cmd-present limine-update; then
  sudo limine-update
elif command -v mkinitcpio &>/dev/null; then
  sudo mkinitcpio -P
fi

omarchy-state set reboot-required
