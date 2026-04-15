# Work around cross-GPU EGL / DMA-BUF incompatibility on hybrid NVIDIA + iGPU laptops.
#
# Hyprland composites on the integrated GPU (Intel/AMD) while GLVND loads NVIDIA EGL
# first (10_nvidia.json priority 10 vs Mesa's 50_mesa.json priority 50). Chromium
# therefore defaults to NVIDIA EGL and tries to import its DMA-BUF buffers as
# EGLImages on the iGPU side, failing with EGL_BAD_MATCH and producing black
# screens, flicker, and GPU process crashes.
#
# Fix: for Chromium only, force Mesa EGL (same GPU as the compositor) via a user
# desktop file override. System-wide EGL is left alone so every other app keeps
# NVIDIA EGL where it needs it.
#
# See: https://github.com/basecamp/omarchy/issues/4901

STOCK_DESKTOP=/usr/share/applications/chromium.desktop
USER_DESKTOP="$HOME/.local/share/applications/chromium.desktop"
MESA_EGL=/usr/share/glvnd/egl_vendor.d/50_mesa.json

# Nothing to override, required bits missing, or user already has an override
[[ -f $STOCK_DESKTOP ]] || exit 0
[[ -f $MESA_EGL ]] || exit 0
[[ -f $USER_DESKTOP ]] && exit 0

# Only act when NVIDIA discrete + non-NVIDIA iGPU are both present
NVIDIA_GPU="$(lspci | grep -iE 'vga|3d|display' | grep -i 'nvidia')"
IGPU="$(lspci | grep -iE 'vga|3d|display' | grep -iv 'nvidia' | grep -iE 'intel|amd|advanced micro devices|radeon|ati ')"

[[ -n $NVIDIA_GPU && -n $IGPU ]] || exit 0

# Match VAAPI driver to the iGPU so libva doesn't fall back to NVIDIA's driver
if echo "$IGPU" | grep -qi 'intel'; then
  VAAPI_DRIVER="iHD"
else
  VAAPI_DRIVER="radeonsi"
fi

mkdir -p "$(dirname "$USER_DESKTOP")"

# Rewrite every Exec= line so Desktop Actions (new-window, incognito) get the fix too
sed -E "s|^Exec=(/usr/bin/chromium.*)|Exec=env __EGL_VENDOR_LIBRARY_FILENAMES=$MESA_EGL LIBVA_DRIVER_NAME=$VAAPI_DRIVER \\1|" \
  "$STOCK_DESKTOP" >"$USER_DESKTOP"
