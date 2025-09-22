echo "Add Omarchy Package Repository"

omarchy-refresh-pacman-mirrorlist

if ! grep -q "omarchy" /etc/pacman.conf; then
  sudo sed -i '/^\[core\]/i [omarchy]\nSigLevel = Optional TrustAll\nServer = https:\/\/pkgs.omarchy.org\/$arch\n' /etc/pacman.conf
  sudo systemctl restart systemd-timesyncd
  sudo pacman -Syu --noconfirm
fi
