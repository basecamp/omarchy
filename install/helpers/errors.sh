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

# Track if we're already handling an error to prevent double-trapping
ERROR_HANDLING=false

# Cursor is usually hidden while we install
show_cursor() {
  printf "\033[?25h"
}

# Display truncated log lines from the install log
show_log_tail() {
  if [[ -f $OMARCHY_INSTALL_LOG_FILE ]]; then
    local log_lines=$((TERM_HEIGHT - LOGO_HEIGHT - 35))
    local max_line_width=$((LOGO_WIDTH - 4))

    tail -n $log_lines "$OMARCHY_INSTALL_LOG_FILE" | while IFS= read -r line; do
      if ((${#line} > max_line_width)); then
        local truncated_line="${line:0:$max_line_width}..."
      else
        local truncated_line="$line"
      fi

      gum style "$truncated_line"
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
  # Store exit code before any conditionals or assignments overwrite $?. EXIT
  # trap callers pass their already-preserved code because calling this function
  # would otherwise reset $? before we can read it.
  local exit_code="${1:-$?}"

  # Prevent recursive error handling
  if [[ $ERROR_HANDLING == "true" ]]; then
    return
  else
    ERROR_HANDLING=true
  fi

  stop_log_output

  if [[ -n ${OMARCHY_CHROOT_FINALIZER:-} ]]; then
    {
      echo "Omarchy installation stopped inside offline finalizer."
      echo "This command halted with exit code $exit_code:"
      if [[ -n ${CURRENT_SCRIPT:-} ]]; then
        echo "Failed script: $CURRENT_SCRIPT"
      else
        echo "$BASH_COMMAND"
      fi
      echo "The live ISO orchestrator will show the visible error screen."
    } >&2
    exit "$exit_code"
  fi

  restore_outputs

  clear_logo
  show_cursor

  gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Omarchy installation stopped!"
  show_log_tail

  gum style "This command halted with exit code $exit_code:"
  show_failed_script_or_command

  gum style "$QR_CODE"
  echo
  gum style "Get help from the community via QR code or at https://discord.gg/tXFUdasqhY"

  # Offer options menu
  while true; do
    options=()

    if install_mode_is online; then
      options+=("Retry installation")
    fi

    # Add upload option if internet is available
    if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
      options+=("Upload log for support")
    fi

    # Add remaining options
    options+=("View full log")
    options+=("Exit")

    choice=$(gum choose "${options[@]}" --header "What would you like to do?" --height 6 --padding "1 $PADDING_LEFT")

    case "$choice" in
    "Retry installation")
      OMARCHY_INSTALL_MODE="$OMARCHY_INSTALL_MODE" bash "$OMARCHY_PATH/install.sh"
      break
      ;;
    "View full log")
      if command -v less &>/dev/null; then
        less "$OMARCHY_INSTALL_LOG_FILE"
      else
        tail "$OMARCHY_INSTALL_LOG_FILE"
      fi
      ;;
    "Upload log for support")
      omarchy-upload-log
      ;;
    "Exit" | "")
      exit "$exit_code"
      ;;
    esac
  done
}

# Exit handler - ensures cleanup happens on any exit
exit_handler() {
  local exit_code=$?

  # Only run if we're exiting with an error and haven't already handled it
  if (( exit_code != 0 )) && [[ $ERROR_HANDLING != "true" ]]; then
    catch_errors "$exit_code"
  else
    stop_log_output
    [[ -n ${OMARCHY_CHROOT_FINALIZER:-} ]] || show_cursor
  fi
}

# Set up traps
trap catch_errors ERR INT TERM
trap exit_handler EXIT

# Save original outputs in case we trap
save_original_outputs
