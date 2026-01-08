# Reference: https://wiki.archlinux.org/title/NVIDIA | https://wiki.archlinux.org/title/Dynamic_Kernel_Module_Support
echo "Migrate legacy NVIDIA GPUs to nvidia-580xx driver (if needed)"

NVIDIA="$(lspci | grep -i 'nvidia')"

if [[ -z $NVIDIA ]]; then
  echo "No NVIDIA GPU detected. Aborting."
  exit 0
fi

echo "Detected NVIDIA GPU(s):"
echo "$NVIDIA"
echo

# If GPU is GTX 9xx or 10xx (Maxwell / Pascal), FORCE migration to legacy 580xx DKMS stack,
# otherwise use nvidia-open-dkms stack.
if echo "$NVIDIA" | grep -qE "GTX 9|GTX 10"; then
  DRIVER_PKGS=(omarchy/nvidia-580xx-dkms omarchy/nvidia-580xx-utils omarchy/lib32-nvidia-580xx-utils)
else
  DRIVER_PKGS=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils)
fi

# Collect Omarchy-supported kernels and their headers
mapfile -t KERNELS < <(
  pacman -Qqe \
    | grep -E '^linux(-zen|-lts|-hardened)?$' \
    | sed 's/$/-headers/'
)

if [[ ${#KERNELS[@]} -eq 0 ]]; then
  echo "No omarchy supported kernels found (linux, linux-zen, linux-lts, linux-hardened). Aborting."
  exit 1
fi

# Extra safety: ensure at least one headers package is actually installed
if ! pacman -Qq | grep -qE '^linux(-[a-z0-9]+)?-headers$'; then
  echo "Error: no linux headers package installed (required for DKMS drivers). Please install the appropriate headers and re-run this migration."
  exit 1
fi

echo "Reinstalling kernel headers: ${KERNELS[*]}"
yes | sudo pacman -S "${KERNELS[@]}"

echo "Installing / updating NVIDIA driver packages: ${DRIVER_PKGS[*]}"
yes | sudo pacman -S "${DRIVER_PKGS[@]}"

# Verify legacy 580xx packages when applicable
if echo "$NVIDIA" | grep -qE "GTX 9|GTX 10"; then
  if ! pacman -Qq nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils &>/dev/null; then
    echo "Error: NVIDIA 580xx driver packages failed to install"
    exit 1
  fi
fi

if command -v dkms > /dev/null 2>&1; then
  sudo dkms autoinstall --force
  sudo depmod -a
fi

if command -v mkinitcpio > /dev/null 2>&1; then
  sudo mkinitcpio -P
else
  echo "mkinitcpio not found; skipping initramfs rebuild."
fi

