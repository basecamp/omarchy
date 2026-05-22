stop_install_log

# Offline ISO installs run inside arch-chroot while the live ISO orchestrator
# owns the visible UI. Never prompt from here: stdout/stderr may be captured to
# logs, leaving gum waiting invisibly on /dev/tty. The live orchestrator shows
# the final "installed in ... / reboot" screen after validation.
if install_mode_is offline; then
  # Never risk an interactive sudo prompt in the chrooted ISO route. The
  # orchestrator removes this shim after finalize.sh returns.
  touch /var/tmp/omarchy-install-completed
  return 0 2>/dev/null || exit 0
fi

echo_in_style() {
  echo "$1" | tte --canvas-width 0 --anchor-text c --frame-rate 640 print
}

clear
echo
tte -i $OMARCHY_PATH/logo.txt --canvas-width 0 --anchor-text c --frame-rate 920 laseretch
echo

# Display installation time if available
if [[ -f $OMARCHY_INSTALL_LOG_FILE ]] && grep -q "Total:" "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null; then
  echo
  TOTAL_TIME=$(tail -n 20 "$OMARCHY_INSTALL_LOG_FILE" | grep "^Total:" | sed 's/^Total:[[:space:]]*//')
  if [[ -n $TOTAL_TIME ]]; then
    echo_in_style "Installed in $TOTAL_TIME"
  fi
else
  echo_in_style "Finished installing"
fi

if sudo test -f /etc/sudoers.d/99-omarchy-installer; then
  sudo rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null
fi

# Exit gracefully if user chooses not to reboot
if gum confirm --padding "0 0 0 $((PADDING_LEFT + 32))" --show-help=false --default --affirmative "Reboot Now" --negative "" ""; then
  # Clear screen to hide any shutdown messages
  clear

  sudo reboot 2>/dev/null
fi
