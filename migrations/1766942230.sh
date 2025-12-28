echo "Migrate legacy NVIDIA GPUs to nvidia-580xx driver (if needed)"

# Only migrate GTX 9xx or 10xx (Pascal/Maxwell)
NVIDIA="$(lspci | grep -i 'nvidia')"
if echo "$NVIDIA" | grep -qE "GTX 9|GTX 10"; then
  # Piping yes to override existing packages
  yes | sudo pacman -S nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils
fi
