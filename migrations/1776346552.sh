echo "Enable Bluetooth A2DP auto-connect in WirePlumber"

mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp $OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf \
  ~/.config/wireplumber/wireplumber.conf.d/

omarchy-restart-pipewire
