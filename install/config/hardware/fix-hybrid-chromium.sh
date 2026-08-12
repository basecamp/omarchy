# Work around cross-GPU EGL / DMA-BUF incompatibility on hybrid NVIDIA + iGPU laptops.
#
# Hyprland composites on the integrated GPU (Intel/AMD) while GLVND loads NVIDIA EGL
# first (10_nvidia.json priority 10 vs Mesa's 50_mesa.json priority 50). Chromium
# therefore defaults to NVIDIA EGL and tries to import its DMA-BUF buffers as
# EGLImages on the iGPU side, failing with EGL_BAD_MATCH and producing black
# screens, flicker, and GPU process crashes.
#
# Fix: for Chromium only, route launches through omarchy-launch-chromium, which
# forces Mesa EGL (same GPU as the compositor) via __EGL_VENDOR_LIBRARY_FILENAMES
# and picks the matching VAAPI driver. System-wide EGL is left alone so every
# other app keeps NVIDIA EGL where it needs it.
#
# See: https://github.com/basecamp/omarchy/issues/4901

STOCK_DESKTOP=/usr/share/applications/chromium.desktop
USER_DESKTOP="$HOME/.local/share/applications/chromium.desktop"
MESA_EGL=/usr/share/glvnd/egl_vendor.d/50_mesa.json
WRAPPER="$OMARCHY_PATH/bin/omarchy-launch-chromium"

# Nothing to override, required bits missing, or user already has an override
[[ -f $STOCK_DESKTOP ]] || exit 0
[[ -f $MESA_EGL ]] || exit 0
[[ -x $WRAPPER ]] || exit 0
[[ -f $USER_DESKTOP ]] && exit 0

# Only act when NVIDIA discrete + non-NVIDIA iGPU are both present
NVIDIA_GPU="$(lspci | grep -iE 'vga|3d|display' | grep -i 'nvidia')"
IGPU="$(lspci | grep -iE 'vga|3d|display' | grep -iv 'nvidia' | grep -iE 'intel|amd|advanced micro devices|radeon|ati ')"

[[ -n $NVIDIA_GPU && -n $IGPU ]] || exit 0

mkdir -p "$(dirname "$USER_DESKTOP")"

# Route every Exec= line through the wrapper so Desktop Actions (new-window,
# incognito) get the fix too. The first token is kept a single command, so
# callers that parse Exec= (like bin/omarchy-launch-browser) keep working.
# Match both Exec=/usr/bin/chromium and bare Exec=chromium, followed by a
# space or end-of-line so we don't accidentally match chromium-browser or
# similar variants.
TMP_DESKTOP=$(mktemp "${USER_DESKTOP}.tmp.XXXXXX") || exit 1
trap 'rm -f "$TMP_DESKTOP"' EXIT

sed -E "s@^Exec=(/usr/bin/chromium|chromium)( |\$)@Exec=$WRAPPER\2@" \
  "$STOCK_DESKTOP" >"$TMP_DESKTOP"

# Verify the substitution actually happened; otherwise we'd leave a dead
# override that blocks future runs (the script exits early if $USER_DESKTOP
# exists). If the stock .desktop format has drifted, bail out cleanly.
if ! grep -q "^Exec=$WRAPPER" "$TMP_DESKTOP"; then
  exit 0
fi

mv "$TMP_DESKTOP" "$USER_DESKTOP"
trap - EXIT
