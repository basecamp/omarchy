#!/bin/bash

# Skip if Asahi (bare metal with its own GPU drivers)
if [ -n "$ASAHI_ALARM" ]; then
  return 0
fi

echo "Detected virtualization requiring software rendering, configuring..."

# Patch imv.desktop for software rendering for all VMs (not just VMware)
imv_desktop="$HOME/.local/share/applications/imv.desktop"
if [[ -f "$imv_desktop" ]]; then
  if ! grep -q "LIBGL_ALWAYS_SOFTWARE=1" "$imv_desktop"; then
    echo "Patching imv.desktop for software rendering..."
    sed -i 's/Exec=imv\(.*\)/Exec=env LIBGL_ALWAYS_SOFTWARE=1 imv\1/' "$imv_desktop"
    echo "imv.desktop configured for software rendering"
  else
    echo "imv.desktop already configured for software rendering"
  fi
fi

# Add imv alias for software rendering to bashrc
bashrc_file="$HOME/.bashrc"
if [[ -f "$bashrc_file" ]]; then
  if ! grep -q "alias imv=" "$bashrc_file"; then
    echo "Adding imv software rendering alias to .bashrc..."
    echo "" >> "$bashrc_file"
    echo "# VM software rendering for imv" >> "$bashrc_file"
    echo "alias imv='LIBGL_ALWAYS_SOFTWARE=1 imv'" >> "$bashrc_file"
    echo "imv alias added to .bashrc"
  else
    echo "imv alias already present in .bashrc"
  fi
fi

# Skip if not a VM requiring software rendering (excludes Parallels which has good GPU support)
if [ -z "$OMARCHY_VM_SOFTWARE_RENDERING" ]; then
  return 0
fi

# Patch envs.conf for VM - add software rendering environment variables
envs_file="$HOME/.local/share/omarchy/default/hypr/envs.conf"
if [[ -f "$envs_file" ]]; then
  # Check if VM rendering vars already exist
  if ! grep -q "VM ARM64 Wayland fixes" "$envs_file"; then
    echo "Patching envs.conf for VM software rendering..."

    # Add VM-specific environment variables at the end of the file
    cat >> "$envs_file" <<'EOF'

# VM ARM64 Wayland fixes (software rendering for VMs without GPU virtualization)
env = WLR_NO_HARDWARE_CURSORS,1
env = WLR_RENDERER_ALLOW_SOFTWARE,1
env = WLR_RENDERER,pixman
env = __GLX_VENDOR_LIBRARY_NAME,mesa
env = LIBGL_ALWAYS_SOFTWARE,1
EOF
    echo "VM rendering configuration added to envs.conf"
  else
    echo "VM rendering configuration already present in envs.conf"
  fi
fi

# Patch LibreOffice desktop entries to disable GPU acceleration
if ls /usr/share/applications/libreoffice-*.desktop &>/dev/null; then
  echo "Configuring LibreOffice desktop entries for software rendering..."
  mkdir -p ~/.local/share/applications

  for system_desktop in /usr/share/applications/libreoffice-*.desktop; do
    local_desktop="$HOME/.local/share/applications/$(basename "$system_desktop")"

    # Copy to user applications dir if not already there or if system version is newer
    if [[ ! -f "$local_desktop" ]] || [[ "$system_desktop" -nt "$local_desktop" ]]; then
      cp "$system_desktop" "$local_desktop"
      echo "Copied $(basename "$system_desktop") to user applications"
    fi

    # Patch if not already patched
    if ! grep -q "SAL_DISABLEOPENGL=1" "$local_desktop"; then
      echo "Patching $(basename "$local_desktop") for software rendering..."
      sed -i 's/Exec=libreoffice/Exec=env SAL_DISABLEOPENGL=1 SAL_NOSKIA=1 libreoffice/' "$local_desktop"
      echo "$(basename "$local_desktop") configured for software rendering"
    else
      echo "$(basename "$local_desktop") already configured for software rendering"
    fi
  done
fi

echo "VM software rendering configuration complete!"
