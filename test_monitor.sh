#!/bin/bash
monitors_to_blank=()
while IFS=':' read -r id name; do
  echo "Found monitor ID: $id, Name: $name"
  monitors_to_blank+=("$name")
done < <(hyprctl monitors -j | jq -r '.[] | "\(.id):\(.name)"')
echo "Monitors to blank: ${monitors_to_blank[@]}"
