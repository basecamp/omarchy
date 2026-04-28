set -e

echo "Enable Bluetooth A2DP auto-connect in WirePlumber"

destination=~/.config/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf

mkdir -p ~/.config/wireplumber/wireplumber.conf.d/

if [[ ! -f "$destination" ]]; then
  cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf" \
    "$destination"
fi

omarchy-restart-pipewire
