#!/bin/bash

state=$(omarchy-shell notifications isDnd 2>/dev/null || echo off)
if [[ $state == "on" ]]; then
  echo '{"text": "󰂛", "tooltip": "Notifications silenced", "class": "active"}'
else
  echo '{"text": ""}'
fi
