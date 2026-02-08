# Install Wi-Fi drivers for Broadcom chips found in some MacBooks, as well as other systems:
# - BCM4360 (2013–2015 MacBooks)
# - BCM4331 (2012, early 2013 MacBooks)

pci_info=$(lspci -nnv)

if (echo "$pci_info" | grep -q "14e4:43a0" || echo "$pci_info" | grep -q "14e4:4331"); then
  echo "BCM4360 / BCM4331 detected"
  # [omarchy] sudo pacman -S --noconfirm --needed broadcom-wl dkms linux-headers
  KERNEL_HEADERS="$(cat /usr/lib/modules/$(uname -r)/pkgbase 2>/dev/null)-headers"
  sudo pacman -S --noconfirm --needed broadcom-wl dkms "$KERNEL_HEADERS"
fi
