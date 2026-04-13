#!/bin/bash
echo "Fix NVIDIA suspend hard-freeze caused by hyprlock holding DRM context (omarchy#5277)"

# Install system-sleep hook on NVIDIA systems
if lspci 2>/dev/null | grep -qi nvidia || lsmod 2>/dev/null | grep -q "^nvidia "; then
  bash "$OMARCHY_PATH/install/config/hardware/nvidia-suspend-hook.sh"
fi

# Resolve the actual desktop user (migrations may run under sudo)
TARGET_USER=""
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="$SUDO_USER"
else
  LOGNAME_USER="$(logname 2>/dev/null || true)"
  if [[ -n "$LOGNAME_USER" && "$LOGNAME_USER" != "root" ]]; then
    TARGET_USER="$LOGNAME_USER"
  fi
fi

TARGET_HOME=""
if [[ -n "$TARGET_USER" ]]; then
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
fi

if [[ -z "$TARGET_HOME" ]]; then
  TARGET_HOME="$HOME"
fi

# Update after_sleep_cmd in hypridle config to relock before enabling the display
HYPRIDLE_CONF="$TARGET_HOME/.config/hypr/hypridle.conf"
if [[ -f "$HYPRIDLE_CONF" ]] && grep -Eq '^[[:space:]]*after_sleep_cmd[[:space:]]*=[[:space:]]*sleep[[:space:]]+1[[:space:]]*&&[[:space:]]*hyprctl[[:space:]]+dispatch[[:space:]]+dpms[[:space:]]+on[[:space:]]*$' "$HYPRIDLE_CONF"; then
  sed -Ei 's|^[[:space:]]*after_sleep_cmd[[:space:]]*=[[:space:]]*sleep[[:space:]]+1[[:space:]]*&&[[:space:]]*hyprctl[[:space:]]+dispatch[[:space:]]+dpms[[:space:]]+on[[:space:]]*$|after_sleep_cmd = omarchy-lock-screen \&\& sleep 2 \&\& hyprctl dispatch dpms on  # relock, wait for render, then turn on display.|' "$HYPRIDLE_CONF"
fi
