echo "Auto-detected ARM architecture: $arch"
echo "Setting OMARCHY_ARM=true"
export OMARCHY_ARM=true

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

# Patch looknfeel.conf for aarch64 - comment out unsupported text_color_inactive option
# Once Hyprland builds an ARM compatible v0.50+ version that adds support for this, patch can be removed
looknfeel_file="$HOME/.local/share/omarchy/default/hypr/looknfeel.conf"
if [[ -f "$looknfeel_file" ]]; then
  # Check if text_color_inactive is still active (not commented)
  if grep -q "^[[:space:]]*text_color_inactive" "$looknfeel_file"; then
    echo "Patching looknfeel.conf for aarch64..."
    # Comment out text_color_inactive line (not supported on ARM Hyprland)
    sed -i 's/^[[:space:]]*text_color_inactive/        # text_color_inactive/' "$looknfeel_file"
  fi
fi
