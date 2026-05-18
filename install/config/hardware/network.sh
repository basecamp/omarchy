# Ensure iwd service will be started
sudo systemctl enable iwd.service

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

# Guarded: only mask if NetworkManager-wait-online exists (for systems using NM)
if [ -f /usr/lib/systemd/system/NetworkManager-wait-online.service ] || systemctl list-unit-files | grep -q '^NetworkManager-wait-online'; then
  sudo systemctl disable --now NetworkManager-wait-online.service 2>/dev/null || true
  sudo systemctl mask NetworkManager-wait-online.service
fi
