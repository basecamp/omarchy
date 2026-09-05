echo "Run the WPA handshake in software on Macs with Broadcom Wi-Fi"

# The install-time quirk only reaches machines set up after it shipped, and it
# never covered Macs without a T2 at all, so an existing install on one still
# cannot join a WPA2/WPA3 transition-mode network. See
# install/hardware/apple/fix-brcmfmac-supplicant.sh for the failure it fixes and
# for where this list of brcmfmac PCI IDs comes from.
dmi_vendor="${OMARCHY_BRCMFMAC_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
dmi_product="${OMARCHY_BRCMFMAC_DMI_PRODUCT:-/sys/class/dmi/id/product_name}"
conf="${OMARCHY_BRCMFMAC_CONF:-/etc/modprobe.d/brcmfmac.conf}"

sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"
product_name="$(cat "$dmi_product" 2>/dev/null || true)"

[[ $product_name != "MacBookPro16,1" ]] || exit 0

if ! lspci -nn | grep "106b:180[12]" >/dev/null &&
  ! { [[ $sys_vendor == Apple* ]] &&
    lspci -nn | grep -E "14e4:(43ba|43bb|43bc|43a3|43dc|4464|4488|4425|4433)" >/dev/null; }; then
  exit 0
fi

# T2 installs already carry this from the installer, so the common case is a
# no-op for the first user and every user after them. Only an active options
# line counts: someone who commented theirs out still needs this.
if [[ -f $conf ]] &&
  grep -Eq '^[[:space:]]*options[[:space:]]+brcmfmac[[:space:]].*feature_disable=0x82000' "$conf"; then
  exit 0
fi

sudo mkdir -p "$(dirname "$conf")"

# Append rather than overwrite, so anything else a user keeps here survives:
# modprobe reads every options line for a module, and nothing else sets
# feature_disable. The leading newline also covers a file that ends without one.
sudo tee -a "$conf" >/dev/null <<'EOF'

# Broadcom's firmware WPA handling fails on affected Apple hardware, which
# surfaces as a rejected password. Disable firmware supplication and SAE so
# transition-mode networks use the software WPA2 handshake instead.
options brcmfmac feature_disable=0x82000
EOF

# modprobe only reads this when the module loads. Reloading brcmfmac here would
# drop a Wi-Fi connection that works on the network the user is on right now,
# including the one carrying this update.
omarchy-state set reboot-required
