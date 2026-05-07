#!/bin/bash

icon=$(omarchy-weather-icon 2>/dev/null)

if [[ -z $icon ]]; then
  printf '{"text":"","tooltip":"","class":"unavailable"}\n'
  exit 0
fi

tooltip=$(omarchy-weather-status 2>/dev/null | tr -d '\n' | sed 's/"/\\"/g')
icon=$(printf '%s' "$icon" | sed 's/"/\\"/g')

printf '{"text":"%s","tooltip":"%s"}\n' "$icon" "$tooltip"
