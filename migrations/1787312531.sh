echo "Unlock 5 GHz Wi-Fi on 2017 Touch Bar MacBook Pros"

# Existing installs never ran the install leaf, so they still only see 2.4 GHz.
# See install/hardware/apple/brcmfmac-43602.sh for the failure this repairs
# and for why the gate is limited to MacBookPro14,2 / 14,3.
: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${OMARCHY_INSTALL:=$OMARCHY_PATH/install}"
# shellcheck source=../install/hardware/apple/brcmfmac-43602.sh
source "$OMARCHY_INSTALL/hardware/apple/brcmfmac-43602.sh"

if brcmfmac43602_needed && ! brcmfmac43602_installed; then
  brcmfmac43602_install

  # The driver only rereads NVRAM when brcmfmac next loads. Reloading it here
  # would drop a Wi-Fi connection that works on the network carrying this update.
  omarchy-state set reboot-required
fi
