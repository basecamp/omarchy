#!/bin/bash

reminder_dir="${XDG_RUNTIME_DIR:-/tmp}/omarchy-reminders"
now=$(date +%s)
count=0
tooltip_lines=()

while IFS=$'\t' read -r timer next; do
  [[ -z $timer || -z $next ]] && continue

  next=$((next / 1000000))
  ((next <= now)) && continue

  remaining=$((next - now))
  minutes=$((remaining / 60))
  reminder=${timer%.timer}
  reminder=${reminder#omarchy-reminder-}
  reminder_minutes=${reminder%%m-*}
  reminder_message=""
  [[ -f $reminder_dir/${timer%.timer}.message ]] && reminder_message=$(<"$reminder_dir/${timer%.timer}.message")

  if [[ -n $reminder_message ]]; then
    tooltip_lines+=("$reminder_message in ${minutes}m")
  else
    tooltip_lines+=("${reminder_minutes}m reminder in ${minutes}m")
  fi

  count=$((count + 1))
done < <(systemctl --user list-timers --all --output=json "omarchy-reminder-*.timer" 2>/dev/null | jq -r '.[] | [.unit, .next] | @tsv')

if ((count == 0)); then
  echo '{"text": ""}'
else
  tooltip=$(printf '%s\n' "${tooltip_lines[@]}")
  tooltip=${tooltip%$'\n'}

  if ((count == 1)); then
    text=$(printf '\U000F009E')
  else
    text=$(printf '\U000F009E %d' "$count")
  fi

  jq -n --arg text "$text" --arg tooltip "$tooltip" \
    '{"text": $text, "tooltip": $tooltip, "class": "active"}'
fi
