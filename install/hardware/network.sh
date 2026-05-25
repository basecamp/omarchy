# NetworkManager enablement is centralized in enable-services.sh.
systemctl disable iwd.service 2>/dev/null || true

# Prevent systemd-networkd-wait-online timeout on boot
systemctl disable systemd-networkd-wait-online.service
systemctl mask systemd-networkd-wait-online.service
