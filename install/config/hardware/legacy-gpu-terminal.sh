# Ghostty requires modern GPU acceleration (OpenGL/Vulkan) which is often unstable
# or missing on legacy hardware. Detect legacy GPU drivers and fall back to Alacritty.

legacy_drivers=("radeon")

for card in /sys/class/drm/card*; do
  if [[ -e $card/device/driver ]]; then
    driver=$(basename "$(readlink -f "$card/device/driver")")

    for legacy in "${legacy_drivers[@]}"; do
      if [[ $driver == $legacy ]]; then
        omarchy-install-terminal alacritty
        exit 0
      fi
    done
  fi
done
