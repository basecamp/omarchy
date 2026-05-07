#!/bin/bash

icon=$(omarchy-weather-icon 2>/dev/null)

if [[ -n $icon ]]; then
  icon=$(printf '%s' "$icon" | sed 's/["\\]/\\&/g')
  printf '{"text":"%s"}\n' "$icon"
else
  printf '{"text":"","class":"unavailable"}\n'
fi
