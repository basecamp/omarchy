# Cap Bluetooth codecs to AAC/SBC-XQ/SBC on Macs with the older Broadcom
# Bluetooth parts named below. See
# default/wireplumber/wireplumber.conf.d/bluez-codec-cap.conf for why. Unlike
# the btusb autosuspend fix, this targets the chip family, not the transport
# it's on - T2 Macs (PCIe hci_bcm4377) get it alongside the USB-attached
# ones, since codec negotiation happens over the Bluetooth link either way.
# Apple Silicon Macs also use hci_bcm4377, but a newer chip generation
# (4377/4378/4387/4388) this fix isn't about, so their Wi-Fi PCI IDs are
# deliberately left out of the match below.
sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"

if lspci -nn | grep "106b:180[12]" >/dev/null ||
  { [[ $sys_vendor == Apple* ]] &&
    lspci -nn | grep -E "14e4:(43a0|4331|43ba|43bb|43bc|43a3|43dc|4464|4488)" >/dev/null; }; then
  mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
  cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/bluez-codec-cap.conf" ~/.config/wireplumber/wireplumber.conf.d/
fi
