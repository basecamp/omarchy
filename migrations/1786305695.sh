echo "Remember the Bluetooth power state across reboots"

marker="${OMARCHY_BLUETOOTH_MIGRATION_MARKER:-/var/lib/omarchy/migrations/1786305695}"
unit_dest="${OMARCHY_BLUETOOTH_STATE_UNIT:-/etc/systemd/system/omarchy-bluetooth-state.service}"

# Everything below is machine-wide, but migration completion is recorded per
# user, so a second account would run it all again and undo whatever an
# administrator changed in between. Grepping for the applied state cannot tell
# "never migrated" from "migrated, then changed on purpose", so record the
# machine. Written last, so an interrupted run is retried rather than skipped.
if [[ -e $marker ]]; then
  exit 0
fi

# An earlier migration set AutoEnable=false believing bluetoothd would then
# restore the adapter's last power state. It has no such behaviour, so the flag
# only ever meant "never power the adapter on" and Bluetooth came up off on
# every boot. Keep the flag and install the piece that was missing.
sudo omarchy-bluetooth-state disable-autoenable

sudo install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-bluetooth-state.service" \
  "$unit_dest"
sudo systemctl daemon-reload

# Record the adapter as it is now, before the unit starts, so the first restore
# does not read the machine as a fresh install and power it on mid-update. seed
# rather than save because save records nothing when it cannot read an adapter.
sudo omarchy-bluetooth-state seed

# Nothing here restarts bluetooth.service, so connected peripherals stay
# connected. Starting the unit now puts its ExecStop in place for the next
# shutdown, capturing the state without a reboot first.
sudo systemctl enable omarchy-bluetooth-state.service

# Only start it if bluetoothd is already up: BindsTo would otherwise pull it up
# for someone who stopped it on purpose, and fail outright if they masked it.
# Left enabled, WantedBy starts it the next time bluetoothd does.
if systemctl is-active --quiet bluetooth.service; then
  sudo systemctl start omarchy-bluetooth-state.service
fi

sudo install -Dm644 /dev/null "$marker"
