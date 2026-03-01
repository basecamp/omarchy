echo "Enable automatic Bluetooth audio device switching"

# Ensure WirePlumber is installed
omarchy-pkg-add wireplumber

# Copy over bluetooth switch config
mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp $OMARCHY_PATH/config/wireplumber/wireplumber.conf.d/51-bluetooth-autoswitch.conf ~/.config/wireplumber/wireplumber.conf.d/

# Restart to pickup new config
systemctl --user restart wireplumber
