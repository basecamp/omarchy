#!/bin/bash
# Auto-detect ARM architecture and set flag
arch=$(uname -m)
if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
  export OMARCHY_ARM=true
  echo "Auto-detected ARM architecture: $arch"
  echo "Setting OMARCHY_ARM=true"

  # ARM/aarch64 architecture override conf files
  ln -sf ~/.local/share/omarchy/default/hypr/aarch64_envs.conf ~/.local/share/omarchy/default/hypr/envs.conf
  ln -sf ~/.local/share/omarchy/default/hypr/aarch64_apps.conf ~/.local/share/omarchy/default/hypr/apps.conf
fi
