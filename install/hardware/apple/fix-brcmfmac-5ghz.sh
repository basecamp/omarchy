# Apple Macs with BCM43602 (2015–2017, PCI 14e4:43ba) only see 2.4 GHz out of
# the box: linux-firmware-broadcom has no board NVRAM, so brcmfmac loads
# placeholder 5 GHz calibration. Install a calibrated copy under
# /usr/lib/firmware/updates so the card advertises the 5 GHz band.
#
# See install/hardware/apple/brcmfmac-43602.sh for the NVRAM provenance and
# why this does not also hard-code a cfg80211 country.

: "${OMARCHY_INSTALL:=${OMARCHY_PATH:-/usr/share/omarchy}/install}"
# shellcheck source=brcmfmac-43602.sh
source "$OMARCHY_INSTALL/hardware/apple/brcmfmac-43602.sh"

if brcmfmac43602_apply; then
  echo "Installed BCM43602 5 GHz NVRAM"
fi
