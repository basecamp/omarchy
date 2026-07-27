#!/bin/bash

# omarchy:summary=Adjust output volume and show the Omarchy OSD
# omarchy:args=<raise|lower|mute-toggle|+N|-N>
# omarchy:examples=omarchy audio output volume raise | omarchy audio output volume lower | omarchy audio output volume mute-toggle | omarchy audio output volume +1

action="${1:-}"

if [[ -z $action ]]; then
  echo "Usage: omarchy-audio-output-volume <raise|lower|mute-toggle|+N|-N>"
  exit 1
fi

# Resolve through any DSP sink to the physical one, so the keys always move real
# loudness and the processing always sees full-scale input. Shared with the audio
# panel and the output switcher.
sink="$(omarchy-audio-output-sink)"
if [[ -z $sink ]]; then
  echo "Could not resolve an audio sink to control." >&2
  exit 1
fi

# pactl reports the same percentage scale wpctl does (both are the raw volume
# over PA_VOLUME_NORM), so the OSD reads identically either way.
volume_percent() {
  pactl get-sink-volume "$sink" 2>/dev/null |
    awk 'NR == 1 {
      for (i = 1; i <= NF; i++)
        if ($i ~ /%$/) {sub("%", "", $i); print $i; exit}
    }'
}

volume_muted() {
  [[ $(pactl get-sink-mute "$sink" 2>/dev/null) == *yes ]]
}

case "$action" in
  raise) action="+5" ;;
  lower) action="-5" ;;
esac

if [[ $action == "mute-toggle" ]]; then
  runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
  debounce_file="$runtime_dir/omarchy-audio-output-volume-mute-toggle.last"
  now=$(date +%s%3N)
  last=0
  [[ -r $debounce_file ]] && read -r last <"$debounce_file" || true
  if ((now - last < 250)); then
    exit 0
  fi
  printf '%s\n' "$now" >"$debounce_file"

  pactl set-sink-mute "$sink" toggle
elif [[ $action =~ ^([+-])([0-9]+)$ ]]; then
  direction="${BASH_REMATCH[1]}"
  step="${BASH_REMATCH[2]}"

  current="$(volume_percent)"
  if [[ -z $current ]]; then
    echo "Could not read volume for $sink." >&2
    exit 1
  fi

  if [[ $direction == "+" ]]; then
    next=$((current + step))
    ((next <= 100)) || next=100
  else
    next=$((current - step))
    ((next >= 0)) || next=0
  fi

  pactl set-sink-mute "$sink" 0
  pactl set-sink-volume "$sink" "${next}%"
else
  echo "Unknown volume action: $action"
  exit 1
fi

percent=$(volume_percent)
if volume_muted || ((${percent:-0} == 0)); then
  icon="volume-muted"
else
  icon="volume-high"
fi

omarchy-osd -i "$icon" -p "${percent:-0}"
