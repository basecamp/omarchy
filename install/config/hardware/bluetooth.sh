# Turn on bluetooth by default
chrootable_systemctl_enable bluetooth.service

mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp $OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf \
  ~/.config/wireplumber/wireplumber.conf.d/
