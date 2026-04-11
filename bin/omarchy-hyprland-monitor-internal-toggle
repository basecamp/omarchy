#!/bin/bash

# Toggle the internal laptop display on/off.
# Useful when connected to an external monitor and you want to close the lid
# or just use the external display only.

INTERNAL=$(hyprctl monitors all -j | jq -r '.[] | select(.name | startswith("eDP")) | .name')

if [[ -z $INTERNAL ]]; then
  notify-send -u low "󰍹    No internal display found"
  exit 1
fi

DISABLED=$(hyprctl monitors all -j | jq -r --arg m "$INTERNAL" '.[] | select(.name == $m) | .disabled')

if [[ $DISABLED == "true" ]]; then
  hyprctl keyword monitor "$INTERNAL,preferred,auto,auto"
  notify-send -u low "󰍹    Internal display on"
else
  hyprctl keyword monitor "$INTERNAL,disable"
  notify-send -u low "󰍹    Internal display off"
fi
