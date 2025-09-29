#!/bin/bash

# Skip if Asahi (bare metal with its own GPU drivers)
if [ -n "$ASAHI_ALARM" ]; then
  exit 0
fi

# Skip if not a VM requiring software rendering (excludes Parallels which has good GPU support)
if [ -z "$OMARCHY_VM_SOFTWARE_RENDERING" ]; then
  exit 0
fi

echo "Detected virtualization requiring software rendering, configuring..."

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

echo "VM software rendering configuration complete!"
