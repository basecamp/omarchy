echo "Migrate legacy NVIDIA GPUs to nvidia-580xx driver (if needed)"

# Only migrate GTX 9xx or 10xx (Pascal/Maxwell)
NVIDIA="$(lspci | grep -i 'nvidia')"
if echo "$NVIDIA" | grep -qE "GTX 9|GTX 10"; then
  omarchy-pkg-drop nvidia nvidia-dkms nvidia-open-dkms nvidia-utils lib32-nvidia-utils
  omarchy-pkg-add nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils
fi
