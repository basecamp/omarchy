# Install Wi-Fi drivers for Broadcom chips on MacBooks:
# - BCM4360 (2013–2015)
# - BCM4331 (2012, early 2013)

pci_info=$(lspci -nnv)

if echo "$pci_info" | grep -q "106b:" && 
  (echo "$pci_info" | grep -q "14e4:43a0" || echo "$pci_info" | grep -q "14e4:4331"); then
  echo "Apple BCM4360 / BCM4331 detected"
  sudo pacman -S --noconfirm --needed broadcom-wl dkms linux-headers
fi
