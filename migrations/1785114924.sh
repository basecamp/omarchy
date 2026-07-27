echo "Fix ASUS ExpertBook B9406 touchpad quirk (takes effect at next login)"

omarchy-hw-asus-expertbook-b9406 || exit 0

sudo rm -f /etc/libinput/asus-expertbook-b9406.quirks
sudo env OMARCHY_PATH="$OMARCHY_PATH" PATH="$PATH" \
  bash -euo pipefail "$OMARCHY_PATH/install/hardware/asus/fix-asus-ptl-b9406-touchpad.sh"
