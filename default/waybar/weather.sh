#!/bin/bash

icon=$(omarchy-weather-icon 2>/dev/null)

if [[ -n $icon ]]; then
  tooltip=$(omarchy-weather-status 2>/dev/null | tr -d '\n' | sed 's/"/\\"/g')
  icon=$(printf '%s' "$icon" | sed 's/"/\\"/g')

  printf '{"text":"%s","tooltip":"%s"}\n' "$icon" "$tooltip"
else
  printf '{"text":"","tooltip":"","class":"unavailable"}\n'
fi
