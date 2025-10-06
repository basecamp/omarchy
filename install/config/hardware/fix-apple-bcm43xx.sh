# Install Wi-Fi drivers for Broadcom chips on MacBooks:
# - BCM4360 (2013–2015)
# - BCM4331 (2012, early 2013)

pci_info=$(lspci -nnv)

if echo "$pci_info" | grep -q "106b:"; then
  if echo "$pci_info" | grep -q "14e4:43a0"; then
    echo "Apple BCM4360 (14e4:43a0) detected — installing broadcom-wl-dkms"
    sudo pacman -S --noconfirm --needed broadcom-wl-dkms dkms linux-headers
  elif echo "$pci_info" | grep -q "14e4:4331"; then
    echo "Apple BCM4331 (14e4:4331) detected — installing broadcom-wl"
    sudo pacman -S --noconfirm --needed broadcom-wl dkms linux-headers
  fi
fi
