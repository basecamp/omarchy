#!/usr/bin/env bash
set -euo pipefail

# Prefer playerctld to unify active player selection
status=$(playerctl -p playerctld status 2>/dev/null || echo "Stopped")
case "$status" in
  Playing) icon="▶️" ;;
  Paused)  icon="⏸️" ;;
  *)       icon="🎵" ;;
esac


info=$(playerctl -a metadata --format "{{ title }} - {{ artist }}")
duration=$(playerctl -a metadata --format "({{duration(position)}}/{{duration(mpris:length)}})")

 


# title=$(playerctl -p playerctld metadata title 2>/dev/null || true)

if [[ $status = "Playing" ]]; then
  printf '{"class":"playing", "text":"%s %s %s"}' "$icon" "$info" "<span class='progress'>$duration</span>"
elif [[ $status = "Paused" ]]; then
  printf '{"class":"paused","text":"%s %s %s"}' "$icon" "$info" "<span class='progress'>$duration</span>"
fi

# # Escape tooltip for JSON using jq if available
# if command -v jq >/dev/null 2>&1; then
#   esc_title=$(printf '%s' "$title" | jq -Rsa .)
# else
#   esc_title="\"${title//\"/\\\"}\""
# fi

# if [[ -n "$title" ]]; then
#   printf '{"text":"%s","tooltip":%s}\n' "$icon" "$esc_title"
# else
#   printf '{"text":"%s","tooltip":"MPRIS"}\n' "$icon"
# fi



