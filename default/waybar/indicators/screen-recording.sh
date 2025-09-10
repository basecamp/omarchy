#!/bin/bash

if pgrep -x wl-screenrec >/dev/null || pgrep -x wf-recorder >/dev/null; then
  echo '{"text": "󰻂", "tooltip": "Stop recording", "class": "recording", "on-click": "omarchy-cmd-screenrecord-stop"}'
else
  echo '{"text": " ", "tooltip": "Not recording", "class": "idle"}'
fi
