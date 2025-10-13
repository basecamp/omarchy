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
  # Accept exit code as parameter (from exit_handler) or capture from $?
  # MUST capture/accept exit code as the VERY FIRST operation (before any if-statements)
  # The if-statement below will reset $? to 0, losing the original error code
  local exit_code=${1:-$?}

  # Prevent recursive error handling
  if [[ $ERROR_HANDLING == "true" ]]; then
    return
  else
    ERROR_HANDLING=true
  fi

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
    gum style -- "--------------------------------------------------------------------------------" # add a divider between the log output and the help text / gum prompt
    echo
    gum style "Get help from the community at https://discord.gg/tXFUdasqhY"
  fi

  # Offer options menu
  while true; do
    options=()

    # If online install, show retry first
    if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
      options+=("Retry installation")
      options+=("Update Omarchy from GitHub, then retry installation")
    fi

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

    echo
    choice=$(gum choose --header "What would you like to do?" "${options[@]}" --height 7 --padding "1 $PADDING_LEFT")

    case "$choice" in
    "Retry installation")
      # Preserve critical environment variables for retry (including log timestamp)
      env \
        OMARCHY_REPO="${OMARCHY_REPO:-}" \
        OMARCHY_REF="${OMARCHY_REF:-}" \
        OMARCHY_USER_NAME="${OMARCHY_USER_NAME:-}" \
        OMARCHY_USER_EMAIL="${OMARCHY_USER_EMAIL:-}" \
        OMARCHY_ONLINE_INSTALL="${OMARCHY_ONLINE_INSTALL:-}" \
        OMARCHY_RETRY_INSTALL=true \
        OMARCHY_LOG_INSTALL_TIMESTAMP="${OMARCHY_LOG_INSTALL_TIMESTAMP:-}" \
        OMARCHY_SIMULATE_AUR_DOWN="${OMARCHY_SIMULATE_AUR_DOWN:-}" \
        OMARCHY_SIMULATE_MIRROR_DOWN="${OMARCHY_SIMULATE_MIRROR_DOWN:-}" \
        SKIP_YARU="${SKIP_YARU:-}" \
        SKIP_OBS="${SKIP_OBS:-}" \
        SKIP_PINTA="${SKIP_PINTA:-}" \
        SKIP_SIGNAL_DESKTOP_BETA="${SKIP_SIGNAL_DESKTOP_BETA:-}" \
        bash ~/.local/share/omarchy/install.sh
      break
      ;;
    "Update Omarchy from GitHub, then retry installation")
      echo
      gum style "Updating Omarchy from GitHub..."

      cd ~/.local/share/omarchy || {
        gum style --foreground 1 "Error: Could not access Omarchy directory"
        continue
      }

      # Check if this is a git repository
      if ! git rev-parse --git-dir > /dev/null 2>&1; then
        # Check if it's a dubious ownership issue
        if git status 2>&1 | grep -q "dubious ownership"; then
          gum style --foreground 3 "Fixing repository ownership..."
          git config --global --add safe.directory ~/.local/share/omarchy || {
            gum style --foreground 1 "Error: Could not configure safe.directory"
            gum style "Please run: git config --global --add safe.directory ~/.local/share/omarchy"
            continue
          }
          # Retry after fixing ownership
          if ! git rev-parse --git-dir > /dev/null 2>&1; then
            gum style --foreground 1 "Error: Omarchy directory is not a git repository"
            gum style "Please delete ~/.local/share/omarchy and run installation again"
            continue
          fi
        else
          gum style --foreground 1 "Error: Omarchy directory is not a git repository"
          gum style "Please delete ~/.local/share/omarchy and run installation again"
          continue
        fi
      fi

      # Stash any local changes (including untracked files)
      local has_changes=false
      if ! git diff-index --quiet HEAD -- || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        has_changes=true
        gum style "  - Stashing local changes (including new files)..."
        if git stash push -u -m "omarchy-install: auto-stash before update $(date +%Y-%m-%d_%H:%M:%S)" 2>&1 | tee /tmp/omarchy-stash.log | grep -v "^hint:" >/dev/null; then
          while IFS= read -r line; do
            [[ -n "$line" ]] && gum style "  - $line"
          done < <(cat /tmp/omarchy-stash.log | grep -v "^hint:")
        else
          gum style --foreground 1 "  - Error: Failed to stash local changes"
          gum style "  - Your changes are preserved. Please manually resolve and retry."
          continue
        fi
      fi

      # Fetch latest changes
      gum style "  - Fetching latest Omarchy..."
      if git fetch origin "${OMARCHY_REF:-master}" 2>&1 | tee /tmp/omarchy-fetch.log | grep -v "^hint:" >/dev/null; then
        while IFS= read -r line; do
          [[ -n "$line" ]] && gum style "  - $line"
        done < <(cat /tmp/omarchy-fetch.log | grep -v "^hint:")
      else
        gum style --foreground 3 "  - Warning: git fetch had issues, continuing anyway..."
      fi

      # Reset to latest
      gum style "  - Updating to latest version..."
      if git reset --hard "origin/${OMARCHY_REF:-master}" 2>&1 | tee /tmp/omarchy-reset.log | grep -v "^hint:" >/dev/null; then
        while IFS= read -r line; do
          [[ -n "$line" ]] && gum style "  - $line"
        done < <(cat /tmp/omarchy-reset.log | grep -v "^hint:")
      else
        gum style --foreground 1 "  - Error: Failed to update Omarchy"
        if [ "$has_changes" = true ]; then
          gum style "  - Your stashed changes are preserved in: git stash list"
        fi
        continue
      fi

      # Apply stashed changes if any (use apply, not pop, to keep stash)
      if [ "$has_changes" = true ]; then
        gum style "  - Reapplying your local changes..."
        if git stash apply 2>&1 | tee /tmp/omarchy-stash-apply.log | grep -q "CONFLICT"; then
          gum style --foreground 1 "  - CONFLICT: Your local changes conflict with the update"
          gum style ""
          while IFS= read -r line; do
            [[ -n "$line" ]] && gum style "    $line"
          done < <(cat /tmp/omarchy-stash-apply.log)
          gum style ""
          gum style "  - Your changes are preserved in the stash. To resolve:"
          gum style "    1. Exit the installer (choose Exit below)"
          gum style "    2. cd ~/.local/share/omarchy"
          gum style "    3. git status  # Review conflicts"
          gum style "    4. Edit conflicting files to resolve"
          gum style "    5. git add <resolved-files>"
          gum style "    6. git stash drop  # After resolving"
          gum style "    7. Re-run installation"
          gum style ""
          gum style --foreground 3 "Press Enter to return to menu..."
          read
          continue
        else
          while IFS= read -r line; do
            [[ -n "$line" ]] && gum style "  - $line"
          done < <(cat /tmp/omarchy-stash-apply.log | grep -v "^hint:")
        fi
      fi

      echo
      gum style --foreground 2 "  - Omarchy updated successfully, restarting installation..."
      sleep 2

      # Restart installation with preserved environment (but NEW log - fresh code = fresh log)
      env \
        OMARCHY_REPO="${OMARCHY_REPO:-}" \
        OMARCHY_REF="${OMARCHY_REF:-}" \
        OMARCHY_USER_NAME="${OMARCHY_USER_NAME:-}" \
        OMARCHY_USER_EMAIL="${OMARCHY_USER_EMAIL:-}" \
        OMARCHY_ONLINE_INSTALL="${OMARCHY_ONLINE_INSTALL:-}" \
        OMARCHY_RETRY_INSTALL=true \
        OMARCHY_SIMULATE_AUR_DOWN="${OMARCHY_SIMULATE_AUR_DOWN:-}" \
        OMARCHY_SIMULATE_MIRROR_DOWN="${OMARCHY_SIMULATE_MIRROR_DOWN:-}" \
        SKIP_YARU="${SKIP_YARU:-}" \
        SKIP_OBS="${SKIP_OBS:-}" \
        SKIP_PINTA="${SKIP_PINTA:-}" \
        SKIP_SIGNAL_DESKTOP_BETA="${SKIP_SIGNAL_DESKTOP_BETA:-}" \
        bash ~/.local/share/omarchy/install.sh
      break
      ;;
    "Show QR code for Discord support")
      gum style "$ASCII_QR_CODE"
      echo
      gum style "Scan QR code or visit: https://discord.gg/tXFUdasqhY"
      ;;
    "View full log")
      # Ensure log file exists before trying to view it
      if [ ! -f "$OMARCHY_INSTALL_LOG_FILE" ]; then
        sudo touch "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null || true
      fi
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
  if [[ $exit_code -ne 0 && $ERROR_HANDLING != true ]]; then
    # Pass exit code as parameter to preserve it through the call
    catch_errors "$exit_code"
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
