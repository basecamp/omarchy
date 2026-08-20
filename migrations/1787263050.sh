echo "Cap Bluetooth codecs to AAC/SBC-XQ/SBC on Macs with Broadcom Bluetooth"

# The install-time fix only reaches machines set up after it shipped. See
# install/user/hardware/apple/fix-bluetooth-codec.sh for the dropout it fixes
# and for where this list of brcmfmac PCI IDs comes from.
dmi_vendor="${OMARCHY_BRCMFMAC_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
conf="$HOME/.config/wireplumber/wireplumber.conf.d/bluez-codec-cap.conf"

sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"

if ! lspci -nn | grep "106b:180[12]" >/dev/null &&
  ! { [[ $sys_vendor == Apple* ]] &&
    lspci -nn | grep -E "14e4:(43a0|4331|43ba|43bb|43bc|43a3|43dc|4464|4488)" >/dev/null; }; then
  exit 0
fi

[[ -f $conf ]] && exit 0

mkdir -p "$(dirname "$conf")"
cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/bluez-codec-cap.conf" "$conf"

# WirePlumber only reads conf.d on startup, and it's already running in this
# session with the old codec list cached; restart it so the cap applies now
# instead of waiting for the next login.
omarchy-restart-audio >/dev/null 2>&1 || true
