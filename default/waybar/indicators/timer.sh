#!/bin/bash

# Waybar custom module script for timer
# If timer is active, it polls every second, if no timer is
# active, it uses inotifywait to wait for a new timer to start.
WATCH_DIR=$XDG_RUNTIME_DIR
ACTIVE_TIMER_FILE=$WATCH_DIR/omarchy-active-timer

format_time() {
  local secs=$1
  if [ $secs -ge 3600 ]; then
      printf "%d:%02d:%02d" $((secs/3600)) $(((secs%3600)/60)) $((secs%60))
  elif [ $secs -ge 60 ]; then
      printf "%d:%02d" $((secs/60)) $((secs%60))
  else
      printf "0:%02d" $secs
  fi
}

# Main loop - runs forever
while true; do
  # If no timer active, output empty and wait for file to appear
  if [ ! -f "$ACTIVE_TIMER_FILE" ]; then
    echo '{"text": "", "alt": "", "tooltip": "", "class": "timer-inactive"}'
    # Wait for the file to be created (blocks until file appears)
    inotifywait -q "$WATCH_DIR" --include "omarchy-active-timer" 2>/dev/null
    continue
  fi

  # Timer is active - update every second
  read TIMER_TYPE END_TIME < "$ACTIVE_TIMER_FILE"
  SECONDS_LEFT=$((END_TIME - $(date +%s)))

  if [ $SECONDS_LEFT -le 0 ]; then
      SECONDS_LEFT=0
  fi

  case "$TIMER_TYPE" in
    t)
      ICON="󱎫 "
      TIMER_TEXT="Timer"
      ;;
    w)
      ICON="󰃖 "
      TIMER_TEXT="Work"
      ;;
    b)
      ICON="  "
      TIMER_TEXT="Break"
      ;;
    *)
      exit 1
      ;;
  esac

  TIME_STR=$(format_time $SECONDS_LEFT)
  echo "{\"text\": \"$ICON \", \"alt\": \"$ICON $TIME_STR \", \"tooltip\": \"$TIMER_TEXT: $TIME_STR remaining\\nRight click to cancel\", \"class\": \"timer-active\"}"
  
  sleep 1
done
