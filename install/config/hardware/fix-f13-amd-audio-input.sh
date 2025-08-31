#!/bin/bash

AMD_AUDIO_CARD=$(pactl list cards | grep -B20 "Family 17h/19h" | grep "Name: " | awk '{print $2}')

if [[ -n $AMD_AUDIO_CARD ]]; then
  pactl set-card-profile "$AMD_AUDIO_CARD" "HiFi (Mic1, Mic2, Speaker)" 2>/dev/null || true
fi
