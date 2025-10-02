# Directs user to Omarchy Discord
QR_CODE='
█▀▀▀▀▀█ ▄ ▄ ▀▄▄▄█ █▀▀▀▀▀█
█ ███ █ ▄▄▄▄▀▄▀▄▀ █ ███ █
█ ▀▀▀ █ ▄█  ▄█▄▄▀ █ ▀▀▀ █
▀▀▀▀▀▀▀ ▀▄█ █ █ █ ▀▀▀▀▀▀▀
▀▀█▀▀▄▀▀▀▀▄█▀▀█  ▀ █ ▀ █
█▄█ ▄▄▀▄▄ ▀ ▄ ▀█▄▄▄▄ ▀ ▀█
▄ ▄▀█ ▀▄▀▀▀▄ ▄█▀▄█▀▄▀▄▀█▀
█ ▄▄█▄▀▄█ ▄▄▄  ▀ ▄▀██▀ ▀█
▀ ▀   ▀ █ ▀▄  ▀▀█▀▀▀█▄▀
█▀▀▀▀▀█ ▀█  ▄▀▀ █ ▀ █▄▀██
█ ███ █ █▀▄▄▀ █▀███▀█▄██▄
█ ▀▀▀ █ ██  ▀ █▄█ ▄▄▄█▀ █
▀▀▀▀▀▀▀ ▀ ▀ ▀▀▀  ▀ ▀▀▀▀▀▀'

ASCII_QR_CODE='
##################################################################
##################################################################
##################################################################
##################################################################
########              ##########  ######  ##              ########
########  ##########  ##  ##  ####        ##  ##########  ########
########  ##      ##  ##########  ##  ##  ##  ##      ##  ########
########  ##      ##  ##        ##  ##  ####  ##      ##  ########
########  ##      ##  ####  ######  ####  ##  ##      ##  ########
########  ##########  ##    ####        ####  ##########  ########
########              ##  ##  ##  ##  ##  ##              ########
##########################    ##  ##  ##  ########################
########          ##        ##        ####  ##  ##  ##  ##########
############  ####  ########    ####  ########  ######  ##########
########  ##  ######  ######  ######    ##########  ##    ########
########      ##    ##    ######  ####          ########  ########
##############    ##  ##      ######    ##    ##  ##      ########
########  ##  ##  ####  ######  ##    ##    ##  ##  ##  ##########
########  ######  ##  ##  ############  ####        ##    ########
########  ##        ##    ##      ########  ##    ######  ########
########  ##  ######  ##  ##  ######              ##  ############
########################  ####  ########  ######    ##############
########              ##    ######    ##  ##  ##  ##      ########
########  ##########  ####  ####  ######  ######    ##    ########
########  ##      ##  ##    ####  ##              ##    ##########
########  ##      ##  ##  ##    ####  ##      ##          ########
########  ##      ##  ##    ####  ##  ##  ########    ##  ########
########  ##########  ##    ########      ##        ####  ########
########              ##  ##  ##      ####  ##            ########
##################################################################
##################################################################
##################################################################
##################################################################'

# Track if we're already handling an error to prevent double-trapping
ERROR_HANDLING=false

# Cursor is usually hidden while we install
show_cursor() {
  printf "\033[?25h"
}

# Display truncated log lines from the install log
show_log_tail() {
  if [[ -f $OMARCHY_INSTALL_LOG_FILE ]]; then
    # On ARM/Asahi/VMs, QR code isn't shown immediately (only as menu option)
    # so we have ~13 more lines available for log output
    local reserved_lines=35
    if [[ -n $OMARCHY_ARM ]] || [[ -n $ASAHI_ALARM ]] || [[ -n $OMARCHY_VIRTUALIZATION ]]; then
      reserved_lines=22
    fi

    local log_lines=$(($TERM_HEIGHT - $LOGO_HEIGHT - $reserved_lines))
    # Ensure we show at least 5 lines even if calculation goes wrong
    [[ $log_lines -lt 5 ]] && log_lines=5

    local max_line_width=$((LOGO_WIDTH - 4))

    tail -n $log_lines "$OMARCHY_INSTALL_LOG_FILE" | while IFS= read -r line; do
      if ((${#line} > max_line_width)); then
        local truncated_line="${line:0:$max_line_width}..."
      else
        local truncated_line="$line"
      fi

      gum style -- "$truncated_line"
    done

    echo
  fi
}

# Display the failed command or script name
show_failed_script_or_command() {
  if [[ -n ${CURRENT_SCRIPT:-} ]]; then
    gum style "Failed script: $CURRENT_SCRIPT"
  else
    # Truncate long command lines to fit the display
    local cmd="$BASH_COMMAND"
    local max_cmd_width=$((LOGO_WIDTH - 4))

    if ((${#cmd} > max_cmd_width)); then
      cmd="${cmd:0:$max_cmd_width}..."
    fi

    gum style "$cmd"
  fi
}

# Save original stdout and stderr for trap to use
save_original_outputs() {
  exec 3>&1 4>&2
}

# Restore stdout and stderr to original (saved in FD 3 and 4)
# This ensures output goes to screen, not log file
restore_outputs() {
  if [[ -e /proc/self/fd/3 ]] && [[ -e /proc/self/fd/4 ]]; then
    exec 1>&3 2>&4
  fi
}

# Error handler
catch_errors() {
  # Prevent recursive error handling
  if [[ $ERROR_HANDLING == "true" ]]; then
    return
  else
    ERROR_HANDLING=true
  fi

  # Store exit code immediately before it gets overwritten
  local exit_code=$?

  stop_log_output
  restore_outputs

  clear_logo
  show_cursor

  gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Omarchy installation stopped!"
  show_log_tail

  gum style "This command halted with exit code $exit_code:"
  show_failed_script_or_command

  # Show QR code immediately on systems with Unicode support
  if [[ -z $OMARCHY_ARM ]] && [[ -z $ASAHI_ALARM ]] && [[ -z $OMARCHY_VIRTUALIZATION ]]; then
    gum style "$QR_CODE"
    echo
    gum style "Get help from the community via QR code or at https://discord.gg/tXFUdasqhY"
  else
    echo
    gum style "Get help from the community at https://discord.gg/tXFUdasqhY"
  fi

  # Offer options menu
  while true; do
    options=()

    # If online install, show retry first
    if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
      options+=("Retry installation")
    # Add QR code option for ARM/Asahi/VMs where screen space is limited
    # because the QR code is rendered with ASCII art instead of Unicode
    if [[ -n $OMARCHY_ARM ]] || [[ -n $ASAHI_ALARM ]] || [[ -n $OMARCHY_VIRTUALIZATION ]]; then
      options+=("Show QR code for Discord support")
    fi

    # Add upload option if internet is available
    if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
      options+=("Upload log for support")
    fi

    # Add remaining options
    options+=("View full log")
    options+=("Exit")

    # Hide help text on ARM/Asahi/VMs (raw TTY can't render it properly)
    local show_help=""
    if [[ -n $OMARCHY_ARM ]] || [[ -n $ASAHI_ALARM ]] || [[ -n $OMARCHY_VIRTUALIZATION ]]; then
      show_help="--show-help=false"
    fi

    choice=$(gum choose "${options[@]}" $show_help --header "What would you like to do?" --height 7 --padding "1 $PADDING_LEFT")

    case "$choice" in
    "Retry installation")
      # Preserve critical environment variables for retry
      env \
        OMARCHY_REPO="${OMARCHY_REPO:-}" \
        OMARCHY_REF="${OMARCHY_REF:-}" \
        OMARCHY_USER_NAME="${OMARCHY_USER_NAME:-}" \
        OMARCHY_USER_EMAIL="${OMARCHY_USER_EMAIL:-}" \
        OMARCHY_ONLINE_INSTALL="${OMARCHY_ONLINE_INSTALL:-}" \
        OMARCHY_RETRY_INSTALL=true \
        bash ~/.local/share/omarchy/install.sh
      break
      ;;
    "Show QR code for Discord support")
      gum style "$ASCII_QR_CODE"
      echo
      gum style "Scan QR code or visit: https://discord.gg/tXFUdasqhY"
      ;;
    "View full log")
      if command -v less &>/dev/null; then
        less "$OMARCHY_INSTALL_LOG_FILE"
      else
        tail "$OMARCHY_INSTALL_LOG_FILE"
      fi
      ;;
    "Upload log for support")
      $OMARCHY_PATH/bin/omarchy-upload-log
      ;;
    "Exit" | "")
      exit 1
      ;;
    esac
  done
}

# Exit handler - ensures cleanup happens on any exit
exit_handler() {
  local exit_code=$?

  # Only run if we're exiting with an error and haven't already handled it
  if (( exit_code != 0 )) && [[ $ERROR_HANDLING != "true" ]]; then
    catch_errors
  else
    stop_log_output
    show_cursor
  fi
}

# Set up traps
trap catch_errors ERR INT TERM
trap exit_handler EXIT

# Save original outputs in case we trap
save_original_outputs
