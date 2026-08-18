echo "Install PipeWire ALSA support on T2 Macs"

# Overlay installs that already ran the old fix-t2.sh have apple-t2-audio-config
# but not PipeWire's ALSA SPA plugin, so WirePlumber never sees the speakers
# (#7347). omarchy-pkg-add is a no-op when the packages are already present.

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

omarchy-pkg-add \
  pipewire-audio \
  pipewire-alsa \
  pipewire-pulse
