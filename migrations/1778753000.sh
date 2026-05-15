echo "Setup Helium managed policy directory and default flags"

sudo mkdir -p /etc/helium/policies/managed
sudo chmod a+rw /etc/helium/policies/managed

if [[ ! -f ~/.config/helium-flags.conf ]]; then
  cp -f "$OMARCHY_PATH/config/chromium-flags.conf" ~/.config/helium-flags.conf
fi
