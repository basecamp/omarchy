#!/bin/bash

get_recorder_process_name() {
  # Use wf-recorder for ARM64 or when running in a VM
  if [[ "$(uname -m)" == "aarch64" ]] || systemd-detect-virt -q; then
    echo "wf-recorder"
  else
    echo "^gpu-screen-recorder"
  fi
}

process_name=$(get_recorder_process_name)

if pgrep -f "$process_name" >/dev/null; then
  echo '{"text": "󰻂", "tooltip": "Stop recording", "class": "active"}'
else
  echo '{"text": ""}'
fi
