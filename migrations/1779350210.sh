echo "Switch Wi-Fi management from iwd to NetworkManager"

omarchy-pkg-add networkmanager

sudo systemctl enable --now NetworkManager.service
sudo systemctl disable --now iwd.service 2>/dev/null || true
omarchy-pkg-drop iwd

nmcli networking on
nmcli radio wifi on

omarchy-state set reboot-required
