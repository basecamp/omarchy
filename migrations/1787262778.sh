echo "Disable btusb autosuspend on Macs with USB-attached Broadcom Bluetooth"

# The install-time fix only reaches machines set up after it shipped. See
# install/hardware/apple/fix-btusb-autosuspend.sh for the dropout it fixes,
# for why T2 Macs are excluded, and for where this PCI ID list comes from.
dmi_vendor="${OMARCHY_BRCMFMAC_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
conf="${OMARCHY_BTUSB_AUTOSUSPEND_CONF:-/etc/modprobe.d/btusb-autosuspend.conf}"

if lspci -nn | grep -E "14e4:(5fa0|5f69|5f71|5f72)" >/dev/null; then
  exit 0
fi

sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"

if ! { [[ $sys_vendor == Apple* ]] &&
  lspci -nn | grep -E "14e4:(43a0|4331|43ba|43bb|43bc|43a3|43dc|4464|4488)" >/dev/null; }; then
  exit 0
fi

[[ -f $conf ]] && exit 0

sudo mkdir -p "$(dirname "$conf")"
echo "options btusb enable_autosuspend=n" | sudo tee "$conf" >/dev/null

omarchy-state set reboot-required
