#!/bin/bash
set -e

echo "Add configurable power profile defaults"

config_dir="${OMARCHY_CONFIG_HOME:-$HOME/.config/omarchy}"

mkdir -p "$config_dir"

if [ ! -f "$config_dir/powerprofiles.conf" ]; then
  if [ -z "${OMARCHY_PATH:-}" ]; then
    echo "OMARCHY_PATH is required to seed power profile defaults" >&2
    exit 1
  fi

  template="$OMARCHY_PATH/config/omarchy/powerprofiles.conf"

  if [ ! -f "$template" ]; then
    echo "Missing power profile defaults: $template" >&2
    exit 1
  fi

  cp "$template" "$config_dir/powerprofiles.conf"
fi
