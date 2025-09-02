#!/bin/bash
# fix-ghost-displays.sh
# Disable phantom MST clones (e.g., Studio Display "ghost" head).
# Keep the monitor entry with MORE available modes; disable the rest.

set -euo pipefail

# Need hyprctl + jq
command -v hyprctl >/dev/null || exit 0
command -v jq >/dev/null || { echo "[ghost-fix] jq not found"; exit 0; }

# Retry a bit in case monitors aren't ready yet
# Wait for monitors to stabilize (especially for hot-plug scenarios)
MON_JSON=""
for i in {1..10}; do
  MON_JSON="$(hyprctl monitors -j 2>/dev/null || true)"
  # Check if we have monitors and if they've stabilized
  if [ -n "$MON_JSON" ] && [ "$MON_JSON" != "[]" ]; then
    # Wait a bit more to ensure all monitors are detected
    sleep 2
    MON_JSON="$(hyprctl monitors -j 2>/dev/null || true)"
    break
  fi
  sleep 1
done
[ -z "$MON_JSON" ] || [ "$MON_JSON" = "[]" ] && exit 0

# Handle escaped JSON from hyprctl (when run via sudo)
MON_JSON=$(echo -e "$MON_JSON")

# Some entries might have null serial; group by serial string key
SERIALS=$(echo "$MON_JSON" | jq -r '[.[].serial // "NULL"] | unique[]')

for SERIAL in $SERIALS; do
  MATCHING=$(echo "$MON_JSON" | jq -c --arg S "$SERIAL" '.[] | select((.serial // "NULL") == $S)')
  COUNT=$(echo "$MATCHING" | wc -l)
  if [ "$COUNT" -gt 1 ]; then
    KEEP=$(echo "$MATCHING" | jq -s 'max_by(.availableModes|length)')
    KEEPID=$(echo "$KEEP" | jq -r '.id')
    echo "[ghost-fix] keeping id=$KEEPID serial=$SERIAL"
    # Disable the rest
    echo "$MATCHING" | jq -r '.name + ":" + (.id|tostring)' | while IFS=: read -r NAME ID; do
      if [ "$ID" != "$KEEPID" ]; then
        echo "[ghost-fix] disabling phantom $NAME (id=$ID) serial=$SERIAL"
        hyprctl keyword monitor "$NAME,disable,add" >/dev/null
      fi
    done
  fi
done