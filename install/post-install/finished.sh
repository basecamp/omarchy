stop_install_log

echo_in_style() {
  echo "$1" | tte --canvas-width 0 --anchor-text c --frame-rate 640 print
}

clear
echo
tte -i ~/.local/share/omarchy/logo.txt --canvas-width 0 --anchor-text c --frame-rate 920 laseretch
echo

# Display installation time if available
if [[ -f $OMARCHY_INSTALL_LOG_FILE ]] && grep -q "Total:" "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null; then
  echo
  TOTAL_TIME=$(tail -n 20 "$OMARCHY_INSTALL_LOG_FILE" | grep "^Total:" | sed 's/^Total:[[:space:]]*//')
  if [ -n "$TOTAL_TIME" ]; then
    echo_in_style "Installed in $TOTAL_TIME"
  fi
else
  echo_in_style "Finished installing"
fi

# Check if we're running as root (in chroot) or need sudo
if [[ $EUID -eq 0 ]]; then
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

# Remove installer sudoers file if it exists (check both possible names)
if $SUDO_CMD test -f /etc/sudoers.d/99-omarchy-installer 2>/dev/null; then
  $SUDO_CMD rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null || true
fi

# Copy installer log to installed system for debugging
# This should work via allow-reboot.sh which creates passwordless sudo for cp/chmod
# Save log to /root/omarchy-install.log (accessible from installed system)
if [[ -f "${OMARCHY_INSTALL_LOG_FILE:-}" ]]; then
  # Copy to /root (accessible from installed system)
  if [[ -d /root ]]; then
    $SUDO_CMD cp "$OMARCHY_INSTALL_LOG_FILE" /root/omarchy-install.log 2>/dev/null || {
      echo "Warning: Could not copy installer log to /root/omarchy-install.log (sudo may require password)" >&2
    }
    $SUDO_CMD chmod 644 /root/omarchy-install.log 2>/dev/null || true
    
    # Log the copy operation
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installer log saved to /root/omarchy-install.log" >>"$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null || true
  fi
fi

# Exit gracefully if user chooses not to reboot
if gum confirm --padding "0 0 0 $((PADDING_LEFT + 32))" --show-help=false --default --affirmative "Reboot Now" --negative "" ""; then
  # Clear screen to hide any shutdown messages
  clear

  if [[ -n "${OMARCHY_CHROOT_INSTALL:-}" ]]; then
    touch /var/tmp/omarchy-install-completed
    exit 0
  else
    # Reboot - should work via allow-reboot.sh sudoers file (passwordless)
    if [[ $EUID -eq 0 ]]; then
      reboot 2>/dev/null
    else
      # Use sudo reboot - should be passwordless via allow-reboot.sh
      $SUDO_CMD reboot 2>/dev/null || {
        echo "Reboot failed. You may need to reboot manually." >&2
        echo "Press Enter to exit..." >&2
        read
      }
    fi
  fi
fi
