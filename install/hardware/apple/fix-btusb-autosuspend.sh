# Linux's btusb driver autosuspends the Bluetooth controller by default,
# repeatedly power-cycling it, which shows up as periodic audio dropouts and
# stutter on Bluetooth headsets/speakers connected to Macs whose Bluetooth is
# USB-attached - a problem macOS doesn't have since its own driver doesn't
# autosuspend the same way. This only fixes machines whose Bluetooth is
# actually on btusb; see the exclusion and inclusion notes below.
sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"

# Bluetooth over PCIe (hci_bcm4377, on T2 Macs and Apple Silicon Macs running
# Asahi) isn't on btusb, so this option has no controller to act on there.
# Check the Bluetooth function's own PCI ID rather than proxying through the
# T2 bridge chip - the bridge tells you a machine has PCIe Bluetooth, but its
# absence doesn't tell you the Bluetooth is on USB (Apple Silicon has PCIe
# Bluetooth with no T2 bridge at all). lspci -nn matches past the point
# grep -q would stop reading, so a match further down its output still needs
# the full pipe drained.
if lspci -nn | grep -E "14e4:(5fa0|5f69|5f71|5f72)" >/dev/null; then
  exit 0
fi

# 14e4:43a0/4331 are the 2012-2015 Macs on the out-of-tree wl driver
# (install/hardware/fix-bcm43xx.sh); the rest are the brcmfmac-driven Wi-Fi
# IDs from install/hardware/apple/fix-brcmfmac-supplicant.sh. Both groups'
# Bluetooth is a Broadcom part on USB.
if [[ $sys_vendor == Apple* ]] &&
  lspci -nn | grep -E "14e4:(43a0|4331|43ba|43bb|43bc|43a3|43dc|4464|4488)" >/dev/null; then
  echo "Detected a Mac with USB-attached Broadcom Bluetooth; disabling btusb autosuspend"

  mkdir -p /etc/modprobe.d
  echo "options btusb enable_autosuspend=n" > /etc/modprobe.d/btusb-autosuspend.conf
fi
