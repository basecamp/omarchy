#!/bin/bash

weather=$(omarchy-weather-status 2>/dev/null)

if [[ -n $weather ]]; then
  read -r icon tooltip <<< "$weather"
  icon=$(printf '%s' "$icon" | sed 's/["\\]/\\&/g')
  tooltip=$(printf '%s' "$tooltip" | sed 's/["\\]/\\&/g')
  printf '{"text":"%s", "tooltip":"%s"}\n' "$icon" "$tooltip"
else
  printf '{"text":"","class":"unavailable"}\n'
fi
