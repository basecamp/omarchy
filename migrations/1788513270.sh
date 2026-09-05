echo "Use software volume for Audient USB audio interfaces"

alsa_procfs="${OMARCHY_ALSA_PROCFS:-/proc/asound}"
audient_cards=()

for usbid in "$alsa_procfs"/card*/usbid; do
  [[ -r $usbid ]] || continue
  [[ $(<$usbid) == 2708:* ]] || continue
  [[ $usbid =~ /card([0-9]+)/ ]] && audient_cards+=("${BASH_REMATCH[1]}")
done

# Seed the rule whether or not an interface is attached: it is inert without one,
# and it has to already be in place for an interface plugged in later.
destination=~/.config/wireplumber/wireplumber.conf.d/audient-soft-mixer.conf
[[ -f $destination ]] || omarchy-refresh-config wireplumber/wireplumber.conf.d/audient-soft-mixer.conf

if (( ${#audient_cards[@]} > 0 )); then
  # Restart before touching the mixer: while the old binding is still live,
  # WirePlumber writes its stored volume straight back into the element below.
  omarchy-restart-audio

  # ACP drove "Speaker Playback Volume" as the sink's hardware volume, so an
  # interface last left mid-attenuation would keep that attenuation now that
  # WirePlumber no longer moves the element. Put it back to 0 dB.
  for card in "${audient_cards[@]}"; do
    amixer -c "$card" sset Speaker 100% >/dev/null 2>&1 || true
  done
fi
