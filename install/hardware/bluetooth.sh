systemctl enable bluetooth.service

# Leave AutoEnable at BlueZ's default. Setting it to false does not make
# bluetoothd remember anything -- BlueZ never persists the Powered property --
# it only means "never power the adapter on", which left Bluetooth off at every
# boot. omarchy-bluetooth-state reapplies whatever the user last chose, and does
# nothing until there is a saved state, so a fresh install still comes up with
# Bluetooth on exactly as stock Arch does.
install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-bluetooth-state.service" \
  /etc/systemd/system/omarchy-bluetooth-state.service
systemctl enable omarchy-bluetooth-state.service
