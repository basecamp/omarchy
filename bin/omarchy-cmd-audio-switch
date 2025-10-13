#!/bin/bash

focused_monitor="$(hyprctl monitors -j | jq -r '.[] | select(.focused == true).name')"

sinks=$(pactl -f json list sinks | jq '[.[] | select((.ports | length == 0) or ([.ports[]? | .availability != "not available"] | any))]')
sinks_count=$(echo "$sinks" | jq '. | length')

if [ "$sinks_count" -eq 0 ]; then
  swayosd-client \
    --monitor "$focused_monitor" \
    --custom-message "No audio devices found"
  exit 1
fi

current_sink_name=$(pactl get-default-sink)
current_sink_index=$(echo "$sinks" | jq -r --arg name "$current_sink_name" 'map(.name) | index($name)')

if [ "$current_sink_index" != "null" ]; then
  next_sink_index=$(((current_sink_index + 1) % sinks_count))
else
  next_sink_index=0
fi

next_sink=$(echo "$sinks" | jq -r ".[$next_sink_index]")
next_sink_name=$(echo "$next_sink" | jq -r '.name')

next_sink_description=$(echo "$next_sink" | jq -r '.description')
if [ "$next_sink_description" = "(null)" ] || [ "$next_sink_description" = "null" ] || [ -z "$next_sink_description" ]; then
  sink_id=$(echo "$next_sink" | jq -r '.properties."object.id"')
  next_sink_description=$(wpctl status | grep -E "\s+\*?\s+${sink_id}\." | sed -E 's/^.*[0-9]+\.\s+//' | sed -E 's/\s+\[.*$//')
fi

next_sink_volume=$(echo "$next_sink" | jq -r \
  '.volume | to_entries[0].value.value_percent | sub("%"; "")')
next_sink_is_muted=$(echo "$next_sink" | jq -r '.mute')

if [ "$next_sink_is_muted" = "true" ] || [ "$next_sink_volume" -eq 0 ]; then
  icon_state="muted"
elif [ "$next_sink_volume" -le 33 ]; then
  icon_state="low"
elif [ "$next_sink_volume" -le 66 ]; then
  icon_state="medium"
else
  icon_state="high"
fi

next_sink_volume_icon="sink-volume-${icon_state}-symbolic"

if [ "$next_sink_name" != "$current_sink_name" ]; then
  pactl set-default-sink "$next_sink_name"
fi

swayosd-client \
  --monitor "$focused_monitor" \
  --custom-message "$next_sink_description" \
  --custom-icon "$next_sink_volume_icon"
