echo "Restore WPA3 support on MacBookPro16,1"

# MacBookPro16,1 carries BCM4364B3 firmware that requires firmware SAE offload
# for WPA3-only networks. Omarchy's 0x82000 quirk disables SAE (bit 19), so
# remove only the exact blocks written by the old T2 installer and the current
# Broadcom setup. Administrator-authored variants remain untouched.
dmi_product="${OMARCHY_BRCMFMAC_DMI_PRODUCT:-/sys/class/dmi/id/product_name}"
conf="${OMARCHY_BRCMFMAC_CONF:-/etc/modprobe.d/brcmfmac.conf}"

product_name="$(cat "$dmi_product" 2>/dev/null || true)"

[[ $product_name == "MacBookPro16,1" ]] || exit 0
[[ -f $conf ]] || exit 0

# Read through sudo so a root-only file fails the migration and gets retried
# rather than reading as empty and burning the per-user migration marker.
content="$(sudo cat "$conf")"

legacy_block='# Fix for T2 MacBook WiFi connectivity issues
options brcmfmac feature_disable=0x82000'

current_block="# Broadcom's firmware supplicant and authenticator fail the WPA four-way
# handshake on Apple hardware, which surfaces as a rejected password. Disable
# both so wpa_supplicant performs the handshake instead.
options brcmfmac feature_disable=0x82000"

if [[ $content == "$legacy_block" ]]; then
  matched_block="$legacy_block"
elif [[ $content == "$current_block" || $content == *$'\n'"$current_block" ]]; then
  matched_block="$current_block"
else
  exit 0
fi

# Request the reboot before editing because brcmfmac reads module options only
# when it loads. Do not reload it during an update carried over Wi-Fi.
omarchy-state set reboot-required

rest=${content%"$matched_block"}
while [[ $rest == *$'\n' ]]; do rest=${rest%$'\n'}; done

if [[ -z $rest ]]; then
  if [[ -L $conf ]]; then
    : | sudo tee "$conf" >/dev/null
  else
    sudo rm -f "$conf"
  fi
else
  printf '%s\n' "$rest" | sudo tee "$conf" >/dev/null
fi
