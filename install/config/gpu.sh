#!/bin/bash

# Detect all GPUs
# https://wiki.hypr.land/Configuring/Multi-GPU/#detecting-gpus
gpu_list=$(lspci -d ::03xx)

gpu_count=$(echo "$gpu_list" | wc -l)

DIR="$(dirname "$(realpath "$0")")"

echo $DIR

if [[ $gpu_count -gt 0 ]]; then
  while read -r line; do
    gpu=$line

    if [[ $(echo "$gpu" | grep -i "intel") ]]; then
      source "$DIR/gpu/intel.sh"
    elif [[ $(echo "$gpu" | grep -i "nvidia") ]]; then
      source "$DIR/gpu/nvidia.sh"
    elif [[ $(echo "$gpu" | grep -i "amd") ]]; then
      #
      # We ignore AMD, because, as I am told, they are Linux-friendly
      # #
      # There are multple GPU designs that we may need to support in the future
      # Non-exhaustive list: Apple, Broadcom (Raspberry) from a total 12 active GPU designers
      #
      printf "%s: %s\n" "Omarchy GPU Setpu: Unknown VGA compatible controllers" $gpu >&2
    fi
  done <<<"$gpu_list"
else
  printf "%s\n" "Omarchy GPU Setup: No VGA compatible controller found" >&2
  echo $gpu_list
fi
