#!/bin/bash

# Ensure elephant is running before launching walker
if ! pgrep -x elephant > /dev/null; then
  setsid uwsm-app -- elephant &
fi

# Ensure walker service is running
if ! pgrep -f "walker --gapplication-service" > /dev/null; then
  setsid uwsm-app -- walker --gapplication-service &
fi

exec walker --width 644 --maxheight 300 --minheight 300 "$@"
