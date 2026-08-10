echo "Remember the Bluetooth power state across reboots"

marker="${OMARCHY_BLUETOOTH_MIGRATION_MARKER:-/var/lib/omarchy/migrations/1786305695}"
unit_dest="${OMARCHY_BLUETOOTH_STATE_UNIT:-/etc/systemd/system/omarchy-bluetooth-state.service}"

# Everything below is machine-wide, but migration completion is recorded per
# user, so a second account on this box would run all of it again. That rerun
# would undo whatever an administrator changed in between: AutoEnable flipped
# back, hand edits to the unit, or the unit disabled outright. Grepping for the
# applied state cannot tell "never migrated" apart from "migrated, then changed
# on purpose", so record the machine instead. Written only at the very end, so
# an interrupted run is retried rather than skipped.
if [[ -e $marker ]]; then
  exit 0
fi

# An earlier migration set AutoEnable=false believing bluetoothd would then
# restore the adapter's last power state. BlueZ has no such behaviour: it never
# writes a Powered key into /var/lib/bluetooth/<adapter>/settings, so the flag
# only ever meant "never power the adapter on" and Bluetooth came up off on
# every boot. Keep the flag, since owning the power-on is what makes the restore
# deterministic, and install the piece that was missing.
sudo omarchy-bluetooth-state disable-autoenable

sudo install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-bluetooth-state.service" \
  "$unit_dest"
sudo systemctl daemon-reload

# Record the adapter as it is right now, before the unit starts. Without this
# the first restore finds no saved state, reads the machine as a fresh install,
# and powers the adapter on mid-update for anyone who deliberately keeps
# Bluetooth off. Seeded, restore matches what is already there and does nothing.
# seed rather than save because save records nothing when it cannot read an
# adapter, and this runs once: a machine left unseeded stays that way.
sudo omarchy-bluetooth-state seed

# Nothing here restarts bluetooth.service, so connected peripherals stay
# connected through the update. Starting the unit now means its ExecStop is in
# place for the next shutdown, so the state is captured without a reboot first.
sudo systemctl enable omarchy-bluetooth-state.service

# Only start it if bluetoothd is already up. The unit is BindsTo=bluetooth.service,
# so starting it otherwise would pull bluetoothd up for someone who stopped it on
# purpose, and fail outright if they masked it. Left enabled,
# WantedBy=bluetooth.service starts it the next time bluetoothd does, by which
# point the seed above is already on disk for restore to read.
if systemctl is-active --quiet bluetooth.service; then
  sudo systemctl start omarchy-bluetooth-state.service
fi

sudo install -Dm644 /dev/null "$marker"
