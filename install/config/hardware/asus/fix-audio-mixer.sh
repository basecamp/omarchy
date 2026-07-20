# Fix audio volume on Asus ROG laptops.
#
# Soft-mixer is required on Asus G14, but breaks on Asus ROG Strix G16 (2025)
# with Realtek ALC285 codec, subsystem id 0x10433f20: the kernel HDA fixup
# re-mutes the Headphone switch after PipeWire opens the device, and
# api.alsa.soft-mixer = true prevents PipeWire from clearing it via the
# standard alsa-card-profile mixer paths (analog-output-headphones.conf).
# See https://github.com/basecamp/omarchy/issues/4821

if omarchy-hw-asus-rog; then
  card=$(aplay -l 2>/dev/null | grep -i "ALC285" | head -1 | sed 's/card \([0-9]*\).*/\1/')

  ssid=""
  if [[ -n $card && -f /proc/asound/card${card}/codec#0 ]]; then
    ssid=$(grep -oE 'Subsystem Id: 0x[0-9a-f]+' /proc/asound/card${card}/codec#0 | awk '{print $3}')
  fi

  case "$ssid" in
    # ASUS ROG Strix G16 (2025) — soft-mixer breaks headphone output here
    0x10433f20)
      rm -f ~/.config/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf
      ;;
    *)
      mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
      cp $OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf ~/.config/wireplumber/wireplumber.conf.d/
      ;;
  esac

  rm -rf ~/.local/state/wireplumber/default-routes

  # Unmute Master and Line Out on the ALC285 card (kernel default is muted/zero).
  # Line Out is the DAC stage feeding the headphone amp on this codec; if it
  # stays at 0 the Headphone jack plays at near-silent levels even when unmuted.
  if [[ -n $card ]]; then
    amixer -c "$card" set Master 80% unmute 2>/dev/null
    amixer -c "$card" set 'Line Out' 80% unmute 2>/dev/null
  fi
fi
