#!/bin/bash

icon=$(omarchy-weather-icon 2>/dev/null)
tooltip=$(omarchy-weather-status 2>/dev/null)

if [[ -n $icon ]]; then
    icon=$(printf '%s' "$icon" | sed 's/["\\]/\\&/g')
    printf '{"text":"%s", "tooltip":"%s"}' "$icon" "$tooltip"
else
    printf '{"text":"","class":"unavailable"}\n'
fi
