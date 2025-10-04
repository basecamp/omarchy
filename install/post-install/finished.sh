stop_install_log

# Use existing width calculations from presentation.sh
# (TERM_WIDTH, PADDING_LEFT, and PADDING_LEFT_SPACES are already set)

echo_in_style() {
  if [ -n "$ASAHI_ALARM" ] || [ -n "$OMARCHY_VIRTUALIZATION" ]; then
    # Calculate manual centering. Can't get --center to work on VM and Asahi consistently
    local text_length=${#1}
    local padding=$(( (TERM_WIDTH - text_length) / 2 ))
    gum style --foreground 48 --bold --padding "0 0 0 $(($padding + 1))" "$1"
  else
    echo "$1" | tte --canvas-width 0 --anchor-text c --frame-rate 640 print
  fi
}

clear
echo

# Asahi and VMs can't handle tte terminal effects, use gum styled text instead
if [ -n "$ASAHI_ALARM" ] || [ -n "$OMARCHY_VIRTUALIZATION" ]; then
  # Gradient colors from top to bottom
  colors=("#F9F9FA" "#D4EEFA" "#98E5FA" "#5CDBFA" "#3ED6F9" "#01CCF9" "#1F99DA" "#3080CC" "#534DB1" "#761B96")

  # Read logo file with absolute whitespace preservation
  line_num=0

  # Use a different approach that preserves all whitespace
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Map 11 lines to 10 gradient colors
    case $line_num in
      0) color_idx=0 ;;  # Line 1: #F9F9FA
      1) color_idx=1 ;;  # Line 2: #D4EEFA
      2) color_idx=1 ;;  # Line 3: #D4EEFA
      3) color_idx=2 ;;  # Line 4: #98E5FA
      4) color_idx=3 ;;  # Line 5: #5CDBFA
      5) color_idx=4 ;;  # Line 6: #3ED6F9
      6) color_idx=5 ;;  # Line 7: #01CCF9
      7) color_idx=6 ;;  # Line 8: #1F99DA
      8) color_idx=7 ;;  # Line 9: #3080CC
      9) color_idx=8 ;;  # Line 10: #534DB1
      *) color_idx=9 ;;  # Line 11+: #761B96
    esac

    # Center each line and apply color using gum's padding option
    gum style --foreground "${colors[$color_idx]}" --bold --padding "0 0 0 $PADDING_LEFT" "$line"
    line_num=$((line_num + 1))
  done < "$OMARCHY_PATH/logo-ascii.txt"

  echo
else
  tte -i "$OMARCHY_PATH/logo.txt" --canvas-width 0 --anchor-text c --frame-rate 920 laseretch
  echo
fi

# Display installation time if available
if [[ -f $OMARCHY_INSTALL_LOG_FILE ]] && grep -q "Total:" "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null; then
  echo
  TOTAL_TIME=$(tail -n 20 "$OMARCHY_INSTALL_LOG_FILE" | grep "^Total:" | sed 's/^Total:[[:space:]]*//')
  if [ -n "$TOTAL_TIME" ]; then
    echo_in_style "Installed in $TOTAL_TIME"
  fi
else
  echo
  echo_in_style "Finished installing"
fi

if sudo test -f /etc/sudoers.d/99-omarchy-installer; then
  sudo rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null
  echo
  echo_in_style "Remember to remove USB installer!"
fi

# Exit gracefully if user chooses not to reboot
if gum confirm --padding "0 0 0 $((PADDING_LEFT + 32))" --show-help=false --default --affirmative "Reboot Now" --negative "" ""; then
  # Clear screen to hide any shutdown messages
  clear

  # Use systemctl if available, otherwise fallback to reboot command
  if command -v systemctl &>/dev/null; then
    systemctl reboot --no-wall 2>/dev/null
  else
    reboot 2>/dev/null
  fi
fi
