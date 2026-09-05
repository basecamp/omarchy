# 2017 Touch Bar MacBook Pros (MacBookPro14,2 / 14,3) with BCM43602 only see
# 2.4 GHz out of the box: linux-firmware-broadcom has no board NVRAM, so
# brcmfmac loads placeholder 5 GHz calibration. Install a calibrated copy
# under /usr/lib/firmware/updates so the card advertises the 5 GHz band.
#
# See install/hardware/apple/brcmfmac-43602.sh for the NVRAM provenance, the
# model gate, and why this does not also hard-code a cfg80211 country.

: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${OMARCHY_INSTALL:=$OMARCHY_PATH/install}"
# shellcheck source=brcmfmac-43602.sh
source "$OMARCHY_INSTALL/hardware/apple/brcmfmac-43602.sh"

if brcmfmac43602_needed && ! brcmfmac43602_installed; then
  brcmfmac43602_install
  echo "Installed BCM43602 5 GHz NVRAM"
fi
