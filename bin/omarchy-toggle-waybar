#!/bin/bash

if pgrep -x waybar >/dev/null; then
  pkill -x waybar
else
  uwsm app -- waybar >/dev/null 2>&1 &
fi
