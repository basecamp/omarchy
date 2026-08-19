# Fix audio volume on Asus ROG laptops by using a soft mixer.

if omarchy-hw-asus-rog; then
  mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
  cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf" ~/.config/wireplumber/wireplumber.conf.d/
  rm -rf ~/.local/state/wireplumber/default-routes

  # With the soft mixer, PipeWire no longer manages the hardware mixer, so any
  # controls muted by default stay muted. Unmute the analog playback path on the
  # Realtek codec (ALC285, ALC294, ...) and let the codec switch between speaker
  # and headphones based on jack state.
  card=$(aplay -l 2>/dev/null | grep -iE "ALC[0-9]+ Analog" | head -1 | sed 's/card \([0-9]*\).*/\1/')
  if [[ -n $card ]]; then
    amixer -c "$card" set Master 80% unmute 2>/dev/null
    for control in Headphone Speaker PCM; do
      amixer -c "$card" set "$control" 100% unmute 2>/dev/null
    done
    amixer -c "$card" set "Auto-Mute Mode" Enabled 2>/dev/null
    sudo alsactl store "$card" 2>/dev/null || true
  fi
fi
