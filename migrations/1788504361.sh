echo "Unlock 5 GHz Wi-Fi on MacBookPro13,3"

# PR #7671's earlier migration intentionally skipped this board because its
# 14,2 / 14,3 calibration performs poorly here. Install the separately
# validated MacBookPro13,3 calibration for systems that already ran that
# migration before support for this model arrived.
: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${OMARCHY_INSTALL:=$OMARCHY_PATH/install}"
# shellcheck source=../install/hardware/apple/brcmfmac-43602.sh
source "$OMARCHY_INSTALL/hardware/apple/brcmfmac-43602.sh"

if [[ $(brcmfmac43602_dmi_product) == "MacBookPro13,3" ]] && \
  brcmfmac43602_needed && ! brcmfmac43602_installed; then
  brcmfmac43602_install
  omarchy-state set reboot-required
fi
