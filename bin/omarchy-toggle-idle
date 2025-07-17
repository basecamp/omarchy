#!/bin/bash

if pgrep -x hypridle >/dev/null; then
  pkill -x hypridle
  notify-send "Stop locking computer when idle"
else
  setsid hypridle &>/dev/null &
  notify-send "Now locking computer when idle"
fi
