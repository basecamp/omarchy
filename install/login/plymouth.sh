# Always copy fresh Plymouth theme files and rebuild
sudo mkdir -p /usr/share/plymouth/themes/omarchy
sudo cp -f "$HOME/.local/share/omarchy/default/plymouth"/* /usr/share/plymouth/themes/omarchy/
sudo rm -rf /usr/share/plymouth/themes/omarchy/plymouth 2>/dev/null

# Write Plymouth config directly (plymouth-set-default-theme can silently fail)
sudo mkdir -p /etc/plymouth
sudo tee /etc/plymouth/plymouthd.conf > /dev/null << 'EOF'
[Daemon]
Theme=omarchy
ShowDelay=0
DeviceTimeout=8
EOF

# Rebuild initramfs
if command -v limine-mkinitcpio &>/dev/null; then
  sudo limine-mkinitcpio
else
  sudo mkinitcpio -P
fi
