# Enable all Omarchy system services
# This is run at the end of configuration to minimize daemon reloads
# Note: sddm and ufw are enabled in their respective setup scripts (login/sddm.sh and first-run/firewall.sh)

# Networking
chrootable_systemctl_enable iwd.service
chrootable_systemctl_enable avahi-daemon.service

# Bluetooth
chrootable_systemctl_enable bluetooth.service

# Printing
chrootable_systemctl_enable cups.service
chrootable_systemctl_enable cups-browsed.service

# Docker
chrootable_systemctl_enable docker.service

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

# Single daemon-reload at the end
sudo systemctl daemon-reload

# Restart systemd-resolved for Docker DNS configuration
sudo systemctl restart systemd-resolved
