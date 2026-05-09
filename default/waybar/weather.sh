#!/bin/bash

if weather=$(omarchy-weather-status 2>/dev/null); then
  read -r icon tooltip <<< "$weather"
  if [[ -z $icon || $icon =~ ^[[:alnum:]]+$ ]]; then
    printf '{"text":"","class":"unavailable"}\n'
    exit 0
  fi
  icon=$(printf '%s' "$icon" | sed 's/["\\]/\\&/g')
  tooltip=$(printf '%s' "$tooltip" | sed 's/["\\]/\\&/g')
  printf '{"text":"%s", "tooltip":"%s"}\n' "$icon" "$tooltip"
else
  printf '{"text":"","class":"unavailable"}\n'
fi
