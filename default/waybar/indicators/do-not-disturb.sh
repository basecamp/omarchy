#!/bin/bash

current_mode=$(makoctl mode | grep "do-not-disturb")
# echo "Debug: Current mode is '$current_mode'"

if [[ "$current_mode" == "do-not-disturb" ]]; then
  echo '{"text": "  ", "tooltip": "All notifications are silenced", "class": "active"}'
else
  echo '{"text": ""}'
fi
