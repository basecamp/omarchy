echo "Disable Chromium VAAPI decode/encode flags on NVIDIA systems"

"$OMARCHY_PATH/bin/omarchy-config-chromium-flags" \
  ~/.config/chromium-flags.conf \
  ~/.config/brave-flags.conf \
  ~/.config/chrome-flags.conf \
  ~/.config/microsoft-edge-stable-flags.conf
