echo "Stabilize Radeon VRAM clocks on MacBookPro13,3"

: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${OMARCHY_INSTALL:=$OMARCHY_PATH/install}"
# shellcheck source=../install/hardware/apple/fix-mbp133-amdgpu.sh
source "$OMARCHY_INSTALL/hardware/apple/fix-mbp133-amdgpu.sh"

if (( gpu_found == 1 )); then
  omarchy-state set reboot-required
fi
