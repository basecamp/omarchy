echo "Fix Chromium EGL / DMA-BUF errors on hybrid NVIDIA + iGPU laptops"

# Delegate to the install-time script so install and migration stay in sync.
# The script is idempotent: it exits 0 when the host isn't hybrid NVIDIA + iGPU,
# when Chromium isn't installed, or when the user already has their own
# ~/.local/share/applications/chromium.desktop override.
bash "$OMARCHY_PATH/install/config/hardware/fix-hybrid-chromium.sh"
