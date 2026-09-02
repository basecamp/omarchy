echo "Stop the Apple Studio Display flickering at 5K on T2 Macs"

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

unit="${OMARCHY_APPLE_DISPLAY_UNIT:-/etc/systemd/system/omarchy-apple-display-link.service}"
rule="${OMARCHY_APPLE_DISPLAY_RULE:-/etc/udev/rules.d/90-omarchy-apple-display-link.rules}"

# Both files present is the machine-wide completion state another user's run leaves.
if [[ -f $unit && -f $rule ]]; then
  exit 0
fi

# The Studio Display advertises an HBR2 link, 5K@60 only fits HBR2 with DSC, and
# that path flickers on amdgpu. The service pins the link to HBR3 at boot and on
# every DRM hotplug; see omarchy-hw-apple-display-link.
sudo install -Dm644 "$OMARCHY_PATH/default/udev/apple-display-link.rules" "$rule"
sudo install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-apple-display-link.service" "$unit"
sudo systemctl daemon-reload
sudo udevadm control --reload
sudo systemctl enable --now omarchy-apple-display-link.service
