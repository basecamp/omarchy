#!/bin/bash

if ! pgrep -x hypridle >/dev/null; then
  echo '{"text": "󱫖", "tooltip": "Idle lock system disabled", "class": "active"}'
elif omarchy-toggle-enabled lockscreen-off; then
  echo '{"text": "󱅟", "tooltip": "Lockscreen disabled (Screensaver only)", "class": "active"}'
else
  echo '{"text": ""}'
fi
