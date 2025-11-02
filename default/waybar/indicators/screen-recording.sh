#!/bin/bash

INFO_FILE="/tmp/omarchy_screenrecord.info"

if [ -f "$INFO_FILE" ]; then
  echo '{"text": "󰻂", "tooltip": "Stop recording", "class": "active"}'
else
  echo '{"text": ""}'
fi
