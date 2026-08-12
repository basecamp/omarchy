# Enable HDMI audio auto-profile for AMD/ATI HDMI audio controllers.
# Without this, WirePlumber leaves HDMI audio cards on the "off" profile
# and monitors never appear as audio output devices.

destination=~/.config/wireplumber/wireplumber.conf.d/amd-hdmi-audio-autoactivate.conf

mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/amd-hdmi-audio-autoactivate.conf" \
  "$destination"

# Clear stale "off" profiles for AMD HDMI cards from WirePlumber state,
# otherwise the stored profile overrides auto-profile selection.
wp_state="$HOME/.local/state/wireplumber/default-profile"
if [[ -f $wp_state ]] && lspci -d 1002: 2>/dev/null | grep -qi "audio"; then
  sed -i '/^alsa_card\.pci-.*00\.1=off$/d' "$wp_state"
fi

systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || true
