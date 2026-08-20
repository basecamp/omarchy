# Macs with Broadcom BCM43602 Wi-Fi (MacBook Pro 2015-2017, MacBook 2016+,
# and same-era iMacs) wedge the brcmfmac firmware on the first resume from S3.
# The driver can no longer put the card into D3, so every suspend after that
# fails with pci_pm_suspend returning -EIO and systemd-logind retries it in a
# loop, lighting the panel each time.
#
# Install a sleep hook that detaches the PCI device from brcmfmac before sleep
# and rebinds it on wake, forcing a clean firmware load. Non-Apple systems run
# brcmfmac too without sharing the firmware bug, so the install is gated on the
# DMI vendor like the WPA handshake quirk beside this file. The T2 Macs from
# 2018 on are also out of scope: their Wi-Fi sits on a different PCI bus.
sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"

if [[ $sys_vendor == Apple* ]] && lspci -nn -s 03:00.0 | grep "14e4:43ba" >/dev/null; then
  echo "Detected BCM43602 Wi-Fi; installing a suspend workaround"
  sudo mkdir -p /usr/lib/systemd/system-sleep
  sudo cp -p "$OMARCHY_PATH/default/systemd/system-sleep/brcmfmac-suspend" /usr/lib/systemd/system-sleep/
fi
