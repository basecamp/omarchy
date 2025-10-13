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
  # Gradient colors from top to bottom (ANSI color codes for 8-color terminals)
  colors=("97" "97" "96" "96" "36" "36" "94" "34" "34" "95" "35" "35")

  # Read logo file with absolute whitespace preservation
  line_num=0

  # Use a different approach that preserves all whitespace
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Map lines to gradient colors
    case $line_num in
      0) color_idx=0 ;;
      1) color_idx=1 ;;
      2) color_idx=2 ;;
      3) color_idx=3 ;;
      4) color_idx=4 ;;
      5) color_idx=5 ;;
      6) color_idx=6 ;;
      7) color_idx=7 ;;
      8) color_idx=8 ;;
      9) color_idx=9 ;;
      10) color_idx=10 ;;
      *) color_idx=11 ;;
    esac

    # Center each line and apply color using ANSI escape sequences
    printf "%${PADDING_LEFT}s\033[1;${colors[$color_idx]}m%s\033[0m\n" "" "$line"
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
  if [[ -n $TOTAL_TIME ]]; then
    echo_in_style "Installed in $TOTAL_TIME"
  fi
else
  echo
  echo_in_style "Finished installing"
fi

if sudo test -f /etc/sudoers.d/99-omarchy-installer; then
  sudo rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null
fi

# --negative "": no negative button (press Enter to continue style)
if gum confirm --padding "0 0 0 $((PADDING_LEFT + 32))" --default --affirmative "Reboot Now" --negative "" "" </dev/tty; then
  # Clear screen to hide any shutdown messages
  clear

  if [[ -n ${OMARCHY_CHROOT_INSTALL:-} ]]; then
    touch /var/tmp/omarchy-install-completed
    exit 0
  else
    sudo reboot 2>/dev/null
  fi
fi
