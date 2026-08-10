systemctl enable bluetooth.service

# Hands the power-on to omarchy-bluetooth-state, which reapplies whatever the
# user last chose. With no saved state yet it powers on, so a fresh install
# still comes up with Bluetooth on exactly as stock does.
omarchy-bluetooth-state disable-autoenable

install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-bluetooth-state.service" \
  /etc/systemd/system/omarchy-bluetooth-state.service
systemctl enable omarchy-bluetooth-state.service
