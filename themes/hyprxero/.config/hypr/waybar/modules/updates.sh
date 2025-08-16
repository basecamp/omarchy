#!/bin/bash

# Temporary file to track the last number of updates
cache_file="/tmp/waybar_updates_last"

# Get number of available updates
updates=$(checkupdates 2>/dev/null | wc -l)

# Read last recorded number of updates, if the file exists
last_updates=0
if [ -f "$cache_file" ]; then
  last_updates=$(cat "$cache_file")
fi

# Send a notification only if the number of updates changed and is greater than zero
if [ "$updates" -gt 0 ] && [ "$updates" -ne "$last_updates" ]; then
  notify-send "System Updates" "\n$updates update(s) available"
fi

# Update the cache file
echo "$updates" > "$cache_file"

# Output in JSON format for Waybar
echo "{\"text\": \"$updates\", \"tooltip\": \"\n$updates update(s) available\", \"class\": \"updates\"}"
