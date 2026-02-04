# Install r8168 driver for Realtek RTL8111/8168/8211/8411 ethernet adapters
# Common in ASUS TUF Gaming laptops and other modern systems
if lspci | grep -i "RTL8111\|RTL8168\|RTL8211\|RTL8411"; then
  omarchy-pkg-add linux-headers r8168-lts
  
  # Blacklist problematic r8169 driver
  echo "blacklist r8169" | sudo tee /etc/modprobe.d/blacklist-r8169.conf
  
  # Regenerate initramfs to ensure r8168 loads on boot
  sudo mkinitcpio -P
fi