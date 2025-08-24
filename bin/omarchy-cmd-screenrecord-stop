#!/bin/bash

if pgrep -x wl-screenrec >/dev/null || pgrep -x wf-recorder >/dev/null; then
  pkill -x wl-screenrec
  pkill -x wf-recorder
  notify-send "Screen recording stopped" -t 2000
fi
