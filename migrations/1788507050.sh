echo "Install T1 Touch Bar support on MacBookPro13,3"

: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${OMARCHY_INSTALL:=$OMARCHY_PATH/install}"
# shellcheck source=../install/hardware/apple/t1-touchbar.sh
source "$OMARCHY_INSTALL/hardware/apple/t1-touchbar.sh"

if t1_touchbar_needed && omarchy-pkg-missing apple-ib-drv-dkms; then
  omarchy-pkg-add apple-ib-drv-dkms
  omarchy-state set reboot-required
fi
