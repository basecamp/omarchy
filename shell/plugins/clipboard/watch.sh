#!/bin/bash

set -o pipefail

capture_script=${1:-}
[[ -n $capture_script && -x $capture_script ]] || exit 1

owner_pid=$PPID
watchdog_pid=""

cleanup() {
  local pid

  if [[ -n $watchdog_pid ]]; then
    kill "$watchdog_pid" 2>/dev/null || true
  fi

  for pid in $(jobs -p); do
    [[ $pid == $watchdog_pid ]] && continue
    kill "$pid" 2>/dev/null || true
  done

  wait 2>/dev/null || true
}

stop() {
  cleanup
  exit 0
}

trap cleanup EXIT
trap stop HUP INT TERM

(
  while kill -0 "$owner_pid" 2>/dev/null; do
    sleep 1
  done

  kill -TERM "$$" 2>/dev/null || true
) &
watchdog_pid=$!

OMARCHY_CLIPBOARD_WATCH_MIME=text wl-paste --type text --watch "$capture_script" 2>/dev/null &
OMARCHY_CLIPBOARD_WATCH_MIME=image/png wl-paste --type image/png --watch "$capture_script" 2>/dev/null &

wait
