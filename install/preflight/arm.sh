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

# CRITICAL: Install pipewire-jack early to prevent jack2 conflicts
# Many packages can pull in jack2 as a dependency, but jack2 doesn't work
# properly on ARM/Asahi systems. pipewire-jack provides the jack interface
# and conflicts with jack2, preventing it from being installed.
# This MUST happen before any other package installation.
echo "Installing pipewire-jack to prevent audio dependency conflicts..."
if ! pacman -Q pipewire-jack &>/dev/null; then
  if pacman -Q jack2 &>/dev/null; then
    echo "Found jack2 installed, replacing with pipewire-jack..."
    sudo pacman -Rdd --noconfirm jack2 >/dev/null 2>&1
  fi
  sudo pacman -S --noconfirm --needed pipewire-jack >/dev/null 2>&1 || {
    echo "Error: Failed to install pipewire-jack"
    exit 1
  }
else
  echo "pipewire-jack already installed"
fi
