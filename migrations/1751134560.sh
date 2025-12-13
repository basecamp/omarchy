echo "Add UWSM env"

export OMARCHY_PATH="$HOME/.local/share/omarchy"
export PATH="$OMARCHY_PATH/bin:$PATH"

mkdir -p "$HOME/.config/uwsm/"
cat <<EOF | tee "$HOME/.config/uwsm/env"
export OMARCHY_PATH=$HOME/.local/share/omarchy
export PATH=$OMARCHY_PATH/bin/:$PATH
EOF

# Ensure we have the latest repos and are ready to pull
omarchy-refresh-pacman
sudo systemctl restart systemd-timesyncd
sudo pacman -Sy # Normally not advisable, but we'll do a full -Syu before finishing

mkdir -p ~/.local/state/omarchy/migrations
touch ~/.local/state/omarchy/migrations/1751134560.sh

# Remove old AUR packages to prevent a super lengthy build on old Omarchy installs
omarchy-pkg-drop zoom qt5-remoteobjects wf-recorder wl-screenrec

# Get rid of old AUR packages
bash $OMARCHY_PATH/migrations/1756060611.sh
touch ~/.local/state/omarchy/migrations/1756060611.sh

bash omarchy-update-perform
