echo "Mark the internal trackpad on T2 Macs as internal so disable-while-typing works"

# The install-time fix only reaches machines set up after it shipped, so an
# existing T2 install still has palms moving the cursor while typing. See
# install/hardware/apple/fix-t2-touchpad.sh for the failure and why the hwdb is
# the right place to correct it.
hwdb="${OMARCHY_T2_TOUCHPAD_HWDB:-/etc/udev/hwdb.d/70-omarchy-t2-touchpad.hwdb}"

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

# Machine-wide repair, so the second user on a T2 Mac finds it already done.
if [[ -f $hwdb ]] && grep -q '^ ID_INPUT_TOUCHPAD_INTEGRATION=internal$' "$hwdb"; then
  exit 0
fi

sudo mkdir -p "$(dirname "$hwdb")"
sudo tee "$hwdb" >/dev/null <<'EOF'
# Apple internal keyboard/trackpad, bridged over the T2's virtual USB HCI.
touchpad:usb:v05acp0340:*
 ID_INPUT_TOUCHPAD_INTEGRATION=internal
EOF

sudo systemd-hwdb update

# libinput builds a device's configuration when udev adds the device, so the
# running session keeps the object it created at login, when the trackpad was
# still tagged external. Logging out and back in is enough; a reboot is the
# signal Omarchy has, and it also works.
omarchy-state set reboot-required
