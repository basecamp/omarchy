#!/bin/bash
# SDDM setup with auto-login for smooth Plymouth transition
# Relies on disk encryption + hyprlock for security
echo "Setting up SDDM..."

yay -S --noconfirm --needed sddm

sudo mkdir -p /etc/sddm.conf.d
cat <<EOF | sudo tee /etc/sddm.conf.d/autologin.conf
[Autologin]
User=$USER
Session=hyprland
EOF

# Enable SDDM service
sudo systemctl enable sddm.service

# Disable getty@tty1 since SDDM will handle the display
sudo systemctl disable getty@tty1.service

echo ""
echo "SDDM configured with auto-login!"
echo "SDDM works flawlessly with Hyprland and should provide smooth Plymouth transition."
echo "Reboot to test the smooth transition."
