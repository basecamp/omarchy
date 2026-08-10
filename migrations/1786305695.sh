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

# Record the adapter as it is right now, before the unit starts. Without this
# the first restore finds no saved state, reads the machine as a fresh install,
# and powers the adapter on mid-update for anyone who deliberately keeps
# Bluetooth off. Seeded, restore matches what is already there and does nothing.
if ! omarchy-cmd-missing omarchy-bluetooth-state; then
  sudo omarchy-bluetooth-state save
fi

# Nothing here restarts bluetooth.service, so connected peripherals stay
# connected through the update. Starting the unit now means its ExecStop is in
# place for the next shutdown, so the state is captured without a reboot first.
sudo systemctl enable omarchy-bluetooth-state.service

# Only start it if bluetoothd is already up. The unit is BindsTo=bluetooth.service,
# so starting it otherwise would pull bluetoothd up for someone who stopped it on
# purpose, and fail outright if they masked it. Worse, the save above could not
# read an adapter without a running daemon, so it seeded nothing, and restore
# would then read the machine as a fresh install and power the adapter on. Left
# enabled, WantedBy=bluetooth.service starts it the next time bluetoothd does.
if systemctl is-active --quiet bluetooth.service; then
  sudo systemctl start omarchy-bluetooth-state.service
fi
