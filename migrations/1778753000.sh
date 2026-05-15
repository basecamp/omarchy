echo "Setup Helium managed policy directory and default flags"

sudo mkdir -p /etc/helium/policies/managed
sudo chmod a+rw /etc/helium/policies/managed

if [[ ! -f ~/.config/helium-flags.conf ]]; then
  mkdir -p ~/.config
  cp -f "${OMARCHY_PATH:-$HOME/.local/share/omarchy}/config/chromium-flags.conf" ~/.config/helium-flags.conf
fi
