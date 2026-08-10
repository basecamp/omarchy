echo "Remember the Bluetooth power state across reboots"

# An earlier migration set AutoEnable=false believing bluetoothd would then
# restore the adapter's last power state. BlueZ has no such behaviour: it never
# writes a Powered key into /var/lib/bluetooth/<adapter>/settings, so the flag
# only ever meant "never power the adapter on" and Bluetooth came up off on
# every boot. Keep the flag, since owning the power-on is what makes the restore
# deterministic, and install the piece that was missing.
if [[ -f /etc/bluetooth/main.conf ]]; then
  sudo sed -i 's/^#\?AutoEnable=.*/AutoEnable=false/' /etc/bluetooth/main.conf
fi

sudo install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-bluetooth-state.service" \
  /etc/systemd/system/omarchy-bluetooth-state.service
sudo systemctl daemon-reload
sudo systemctl enable --now omarchy-bluetooth-state.service
