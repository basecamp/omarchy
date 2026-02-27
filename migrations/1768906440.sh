echo "Migrate legacy mobile NVIDIA GPUs to nvidia-580xx driver (if needed)"

# Only migrate MX1xx, 2xx or 3xx (Pascal/Maxwell)
NVIDIA="$(lspci | grep -i 'nvidia')"
if echo "$NVIDIA" | grep -qE "MX1|MX2|MX3"; then
  if ! pacman -Qq | grep -qE '^linux(-[a-z0-9]+)?-headers$'; then
    echo "Error: no linux headers package installed (required for DKMS drivers). Please install the appropriate headers and re-run this migration."
    exit 1
  fi

  # Piping yes to override existing packages
  yes | sudo pacman -S nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils

  # Verify packages were installed
  if ! pacman -Qq nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils &>/dev/null; then
    echo "Error: NVIDIA 580xx driver packages failed to install"
    exit 1
  fi
fi
