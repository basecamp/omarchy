echo "Auto-detected ARM architecture: $arch"
echo "Setting OMARCHY_ARM=true"
export OMARCHY_ARM=true

# Patch envs.conf for aarch64 VMs only - add Vulkan ICD for software rendering
# Skip this for bare metal ARM (Pi, Asahi, etc.) which have real GPUs
envs_file="$HOME/.local/share/omarchy/default/hypr/envs.conf"
if [[ -f "$envs_file" ]]; then
  # Only add lavapipe software renderer for ARM VMs, not bare metal with real GPUs
  if [[ -z "$OMARCHY_ARM_BARE_METAL" ]]; then
    # Check if the Vulkan ICD line already exists
    if ! grep -q "VK_ICD_FILENAMES" "$envs_file"; then
      echo "Patching envs.conf for aarch64 VM (software rendering)..."
      # Find the last env line and add the Vulkan ICD after it
      last_env_line=$(grep -n "^env = " "$envs_file" | tail -1 | cut -d: -f1)
      if [[ -n "$last_env_line" ]]; then
        sed -i "${last_env_line}a\\\\n# Required for walker on aarch64 VMs (software rendering)\\nenv = VK_ICD_FILENAMES,/usr/share/vulkan/icd.d/lvp_icd.aarch64.json" "$envs_file"
      fi
    fi
  else
    echo "ARM bare metal detected - using hardware GPU (skipping lavapipe)"
  fi
fi
