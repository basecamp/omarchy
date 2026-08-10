echo "Stop forcing Bluetooth off at every boot"

# An earlier migration set AutoEnable=false on the theory that bluetoothd would
# then restore the adapter's last power state. BlueZ has no such behaviour: it
# never writes a Powered key into /var/lib/bluetooth/<adapter>/settings, so the
# flag only ever meant "never power the adapter on" and Bluetooth came up off on
# every boot. Put the default back and persist the state properly instead.
if [[ -f /etc/bluetooth/main.conf ]] && grep -q '^AutoEnable=false$' /etc/bluetooth/main.conf; then
  sudo sed -i 's/^AutoEnable=false$/AutoEnable=true/' /etc/bluetooth/main.conf
fi

sudo install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-bluetooth-state.service" \
  /etc/systemd/system/omarchy-bluetooth-state.service
sudo systemctl daemon-reload
sudo systemctl enable omarchy-bluetooth-state.service
