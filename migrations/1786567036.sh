echo "Unmask wpa_supplicant so NetworkManager can bring wifi back"

# iwd-era installs may carry a wpa_supplicant.service mask, which breaks
# NetworkManager's D-Bus activation of the supplicant and leaves every wifi
# device unavailable (#6783).

state=$(systemctl is-enabled wpa_supplicant.service 2>/dev/null || true)
[[ $state == masked* ]] || exit 0

sudo systemctl unmask wpa_supplicant.service

# Older systemds leave a /run mask behind unless asked explicitly.
state=$(systemctl is-enabled wpa_supplicant.service 2>/dev/null || true)
if [[ $state == "masked-runtime" ]]; then
  sudo systemctl unmask --runtime wpa_supplicant.service
fi

# No enable needed: NetworkManager D-Bus-activates the supplicant on demand.
# But it stops retrying after five failures, so restart it when a wifi device
# sits unavailable — except during the live Quattro upgrade, where iwd may
# still carry the connection until the reboot.
if [[ ${OMARCHY_UPGRADE_TO_QUATTRO_LIVE:-0} != "1" ]] &&
  systemctl is-active --quiet NetworkManager.service 2>/dev/null &&
  [[ $(LC_ALL=C nmcli -t -f TYPE,STATE device 2>/dev/null || true) == *"wifi:unavailable"* ]]; then
  sudo systemctl restart NetworkManager.service || true
fi
