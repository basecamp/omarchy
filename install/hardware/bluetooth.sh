systemctl enable bluetooth.service

# AutoEnable=false does not make bluetoothd remember anything, because BlueZ
# never persists the Powered property. It only means "never power the adapter
# on", which is exactly what we want here: omarchy-bluetooth-state owns the
# power-on and reapplies whatever the user last chose. Leaving AutoEnable on
# instead would have BlueZ powering adapters up asynchronously, racing the
# restore and winning. With no saved state yet, restore powers the adapter on,
# so a fresh install still comes up with Bluetooth on exactly as stock does.
if [[ -f /etc/bluetooth/main.conf ]]; then
  sed -i 's/^#\?AutoEnable=.*/AutoEnable=false/' /etc/bluetooth/main.conf
fi

install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-bluetooth-state.service" \
  /etc/systemd/system/omarchy-bluetooth-state.service
systemctl enable omarchy-bluetooth-state.service
