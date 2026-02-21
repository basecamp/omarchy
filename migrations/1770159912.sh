echo "Fix NVIDIA environment variables for Maxwell/Pascal/Volta GPUs"

# Detect if user has Maxwell/Pascal/Volta GPU (pre-Turing cards without GSP firmware)
# Maxwell (GTX 9xx), Pascal (GT/GTX 10xx, Quadro P, MX series), Volta (Titan V, Tesla V100, Quadro GV100)
NVIDIA="$(lspci | grep -i 'nvidia')"
if echo "$NVIDIA" | grep -qE "GTX (9[0-9]{2}|10[0-9]{2})|GT 10[0-9]{2}|Quadro [PM][0-9]{3,4}|Quadro GV100|MX *[0-9]+|Titan (X|Xp|V)|Tesla V100"; then
  ENVS_CONF="$HOME/.config/hypr/envs.conf"

  if [[ -f $ENVS_CONF ]]; then
    # Check if file contains problematic variables
    if grep -qE "env = (NVD_BACKEND,direct|LIBVA_DRIVER_NAME,nvidia)" "$ENVS_CONF"; then
      echo "Removing incompatible NVIDIA environment variables for legacy GPU..."

      # Create backup
      cp "$ENVS_CONF" "$ENVS_CONF.bak.$(date +%s)"

      # Remove all NVIDIA env lines and section headers (we re-add the correct ones below)
      sed -i '/^env = \(NVD_BACKEND\|LIBVA_DRIVER_NAME\|__GLX_VENDOR_LIBRARY_NAME\),/d; /^# NVIDIA/d' "$ENVS_CONF"

      # Add correct environment variables for legacy GPUs
      cat >>"$ENVS_CONF" <<'EOF'

# NVIDIA (Maxwell/Pascal/Volta without GSP firmware)
env = NVD_BACKEND,egl
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
EOF

      echo "NVIDIA environment variables updated. A backup was saved to $ENVS_CONF.bak.*"
      echo "Please restart Hyprland for changes to take effect."
    fi
  fi
fi
