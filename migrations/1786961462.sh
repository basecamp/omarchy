echo "Install the audio-capable kernel on ASUS ExpertBook B9406 systems"

omarchy-hw-asus-expertbook-b9406 || exit 0

sudo env OMARCHY_PATH="$OMARCHY_PATH" PATH="$OMARCHY_PATH/bin:$PATH" \
  bash -euo pipefail "$OMARCHY_PATH/install/hardware/intel/ptl-kernel.sh"

omarchy-state set reboot-required
