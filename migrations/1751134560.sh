echo "Add UWSM env"

export OMARCHY_PATH="$HOME/.local/share/omarchy"
export PATH="$OMARCHY_PATH/bin:$PATH"

mkdir -p "$HOME/.config/uwsm/"
cat <<EOF | tee "$HOME/.config/uwsm/env"
export OMARCHY_PATH=$HOME/.local/share/omarchy
export PATH=$OMARCHY_PATH/bin/:$PATH
EOF

# Remove Zoom/qt5-remoteobjects to prevent a super lengthy build on old Omarchy installs
sudo pacman -Rns --noconfirm zoom qt5-remoteobjects

# Ensure we have the latest repos
omarchy-refresh-pacman-mirrorlist
if ! grep -q "omarchy" /etc/pacman.conf; then
  sudo sed -i '/^\[core\]/i [omarchy]\nSigLevel = Optional TrustAll\nServer = https:\/\/pkgs.omarchy.org\/stable\/$arch\n' /etc/pacman.conf
fi

mkdir -p ~/.local/state/omarchy/migrations
touch ~/.local/state/omarchy/migrations/1751134560.sh

sudo systemctl restart systemd-timesyncd
bash omarchy-update-perform
