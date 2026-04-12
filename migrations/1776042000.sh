#!/bin/bash
echo "Fix NVIDIA suspend hard-freeze caused by hyprlock holding DRM context (omarchy#5277)"

# Install system-sleep hook on NVIDIA systems
if lspci 2>/dev/null | grep -qi nvidia || lsmod 2>/dev/null | grep -q "^nvidia "; then
  bash "$OMARCHY_PATH/install/config/hardware/nvidia-suspend-hook.sh"
fi

# Update after_sleep_cmd in hypridle config to relock before enabling the display
HYPRIDLE_CONF="$HOME/.config/hypr/hypridle.conf"
if [[ -f $HYPRIDLE_CONF ]] && grep -Eq '^[[:space:]]*after_sleep_cmd[[:space:]]*=.*hyprctl[[:space:]]+dispatch[[:space:]]+dpms[[:space:]]+on([[:space:]]|$)' "$HYPRIDLE_CONF"; then
  sed -Ei 's|^[[:space:]]*after_sleep_cmd[[:space:]]*=.*hyprctl[[:space:]]+dispatch[[:space:]]+dpms[[:space:]]+on.*$|after_sleep_cmd = omarchy-lock-screen \&\& sleep 2 \&\& hyprctl dispatch dpms on  # relock, wait for render, then turn on display.|' "$HYPRIDLE_CONF"
fi
