echo "Install missing Mesa Vulkan driver for Intel/AMD/Apple GPUs"

# Backfill for systems installed before install/config/hardware/vulkan.sh existed.
# install/ scripts only run at initial setup, so machines set up earlier never
# received a Mesa Vulkan ICD for their iGPU (leaving e.g. NVIDIA as the only Vulkan
# device on hybrid laptops). omarchy-pkg-add is idempotent, so this is a no-op when
# the driver is already present.

declare -A VULKAN_DRIVERS=(
  [Intel]=vulkan-intel
  [AMD]=vulkan-radeon
  [Apple]=vulkan-asahi
)

PACKAGES=()

for vendor in "${!VULKAN_DRIVERS[@]}"; do
  if lspci | grep -iE "(VGA|Display).*$vendor" >/dev/null; then
    PACKAGES+=("${VULKAN_DRIVERS[$vendor]}")
  fi
done

if (( ${#PACKAGES[@]} > 0 )); then
  omarchy-pkg-add "${PACKAGES[@]}"
fi
