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
# If GPU is GTX 9xx or 10xx (Maxwell / Pascal), FORCE migration to legacy 580xx DKMS stack, Turing+ USE the nvidia-open-dkms
if echo "$NVIDIA" | grep -qE "GTX 9|GTX 10"; then
  DRIVER_PKGS=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
else
  DRIVER_PKGS=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils)
fi
mapfile -t KERNELS < <(pacman -Qqe \
  | grep -E '^linux(-zen|-lts|-hardened)?$' \
  | sed 's/$/-headers/')
if [[ ${#KERNELS[@]} -eq 0 ]]; then
  echo "No omarchy supported kernels found (linux, linux-zen, linux-lts, linux-hardened). Aborting."
  exit 1
fi
  # Piping yes to override existing packages
yes | sudo pacman -S "${KERNELS[@]}"
yes | sudo pacman -S "${DRIVER_PKGS[@]}"
if command -v dkms > /dev/null 2>&1; then
  sudo dkms autoinstall --force
  sudo depmod -a
fi
if command -v mkinitcpio > /dev/null 2>&1; then
  sudo mkinitcpio -P
else
  echo "mkinitcpio not found; skipping initramfs rebuild."
fi
