#!/bin/bash

if pgrep -x wl-screenrec >/dev/null || pgrep -x wf-recorder >/dev/null; then
  echo '{"text": "⏺", "tooltip": "Recording in progress", "class": "recording"}'
else
  echo '{"text": "", "tooltip": "Not recording", "class": "idle"}'
fi
