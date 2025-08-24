#!/bin/bash

# handle click events from waybar
if [[ "$1" == "toggle" ]]; then
  makoctl mode -t do-not-disturb
  if makoctl mode | grep -q 'do-not-disturb'; then
    notify-send "Silenced notifications"
  else
    notify-send "Enabled notifications"
  fi
fi

# get current mode (take only the last line to avoid multiple modes)
CURRENT_MODE=$(makoctl mode | tail -n 1)

# determine icon and class based on mode
if [[ "$CURRENT_MODE" == "do-not-disturb" ]]; then
  ICON=""
  CLASS="notifications-silenced"
else
  ICON=""
  CLASS="notifications-enabled"
fi

# output (JSON)
echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"Notifications: $CURRENT_MODE\"}"
