# Logitech MX Keys / MX Keys S: the MX Keys S action row (emoji, screenshot,
# dictation, mic mute, lock) sends fixed chords meant for Logi Options+, which
# does not exist on Linux; the MX Keys has no such row, but its Super+A / Super+D
# Fn-layer keys do nothing here and its lock key's Super+L toggles the workspace
# layout. When either keyboard is present -- over Bluetooth, a Unifying receiver
# or the Bolt receiver -- remap it with keyd so the keys reach their Omarchy
# equivalents. See default/keyd/logitech-mx-keys.conf and
# default/hypr/bindings/logitech-mx-keys.lua.
#
# Also invoked by migrations/1787838885.sh for existing installs. Re-run by hand
# with `bash "$OMARCHY_PATH/install/hardware/logitech-mx-keys.sh"` if the
# keyboard was asleep the first time.

# The Bolt probe opens /dev/hidraw* read/write and needs root (the sysfs scan
# for Bluetooth / Unifying does not). During install this script already runs as
# root; from the migration it runs as the user, so elevate the probe there.
mx_keys_hw() {
  if [[ $EUID -eq 0 ]]; then
    omarchy-hw-logitech-mx-keys "$@"
  else
    sudo "$OMARCHY_PATH/bin/omarchy-hw-logitech-mx-keys" "$@"
  fi
}

if mx_keys_ids=$(mx_keys_hw --keyd-ids) && [[ -n $mx_keys_ids ]]; then
  omarchy-pkg-add keyd

  # Build [ids] from what the detector actually found -- never ship the Bolt
  # receiver id on a machine where the MX Keys S is only on Bluetooth, or a
  # Unifying keyboard's own id on a machine that has no such keyboard.
  {
    printf '[ids]\n%s\n\n' "$mx_keys_ids"
    cat "$OMARCHY_PATH/default/keyd/logitech-mx-keys.conf"
  } | sudo tee /etc/keyd/logitech-mx-keys.conf >/dev/null
  sudo chmod 644 /etc/keyd/logitech-mx-keys.conf

  # restart, not just enable --now: keyd may already be running for another
  # keyboard, in which case only a restart picks up this new config file.
  sudo systemctl enable keyd.service
  sudo systemctl restart keyd.service
fi
