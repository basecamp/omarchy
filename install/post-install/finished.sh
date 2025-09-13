stop_install_log

clear
tte -i ~/.local/share/omarchy/logo.txt --canvas-width 0 --anchor-text c --frame-rate 920 laseretch
echo
echo
echo "You're done!" | tte --canvas-width 0 --anchor-text c --frame-rate 640 wipe

# Display installation time if available
if [[ -f $OMARCHY_INSTALL_LOG_FILE ]] && grep -q "Total:" "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null; then
  echo
  echo
  TOTAL_TIME=$(tail -n 20 "$OMARCHY_INSTALL_LOG_FILE" | grep "^Total:" | sed 's/^Total:[[:space:]]*//')
  if [ -n "$TOTAL_TIME" ]; then
    echo "Installation completed in $TOTAL_TIME" | tte --canvas-width 0 --anchor-text c --frame-rate 200 waves
  fi
fi

if sudo test -f /etc/sudoers.d/99-omarchy-installer; then
  sudo rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null
  echo
  echo "Remember to remove USB installer!" | tte --canvas-width 0 --anchor-text c --frame-rate 640 wipe
fi

# Exit gracefully if user chooses not to reboot
if gum confirm --padding "1 0 0 $PADDING_LEFT" --default --affirmative "Reboot Now" --negative "" ""; then
  # Clear screen to hide any shutdown messages
  clear

  # Use systemctl if available, otherwise fallback to reboot command
  if command -v systemctl &>/dev/null; then
    systemctl reboot --no-wall 2>/dev/null
  else
    reboot 2>/dev/null
  fi
fi
