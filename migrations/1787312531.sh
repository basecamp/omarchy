echo "Unlock 5 GHz Wi-Fi on BCM43602 Macs"

# Existing installs never ran the install leaf, so they still only see 2.4 GHz.
# See install/hardware/apple/brcmfmac-43602.sh for the failure this repairs.
: "${OMARCHY_INSTALL:=${OMARCHY_PATH:-/usr/share/omarchy}/install}"
# shellcheck source=../install/hardware/apple/brcmfmac-43602.sh
source "$OMARCHY_INSTALL/hardware/apple/brcmfmac-43602.sh"

if brcmfmac43602_apply; then
  # The driver only rereads NVRAM when brcmfmac next loads. Reloading it here
  # would drop a Wi-Fi connection that works on the network carrying this update.
  omarchy-state set reboot-required
fi
