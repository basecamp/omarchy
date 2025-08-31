#!/bin/bash
# Auto-detect ARM architecture and set flag
arch=$(uname -m)
if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
  export OMARCHY_ARM=true
  echo "Auto-detected ARM architecture: $arch"
  echo "Setting OMARCHY_ARM=true"
  
  # Patch envs.conf for aarch64 - add Vulkan ICD for walker
  envs_file="$HOME/.local/share/omarchy/default/hypr/envs.conf"
  if [[ -f "$envs_file" ]]; then
    # Check if the Vulkan ICD line already exists
    if ! grep -q "VK_ICD_FILENAMES" "$envs_file"; then
      echo "Patching envs.conf for aarch64..."
      # Find the last env line and add the Vulkan ICD after it
      last_env_line=$(grep -n "^env = " "$envs_file" | tail -1 | cut -d: -f1)
      if [[ -n "$last_env_line" ]]; then
        sed -i "${last_env_line}a\\\\n# Required for walker on aarch64\\nenv = VK_ICD_FILENAMES,/usr/share/vulkan/icd.d/lvp_icd.aarch64.json" "$envs_file"
      fi
    fi
  fi

fi
