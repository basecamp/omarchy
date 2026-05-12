# Turn on bluetooth by default
chrootable_systemctl_enable bluetooth.service

# Persist last power state across reboots (default AutoEnable=true overrides it)
sudo sed -i 's/^#\?AutoEnable=.*/AutoEnable=false/' /etc/bluetooth/main.conf

mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf" ~/.config/wireplumber/wireplumber.conf.d/
