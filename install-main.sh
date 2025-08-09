#!/bin/bash
# Omarchy installation script - main installer that runs inside Cage
# journalctl -t omarchy-install
set -eE

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# TEST_MODE can be set via environment variable, defaults to false
TEST_MODE="${TEST_MODE:-false}"
PROGRESS_LINES=10 # Number of progress lines to show below spinner
OMARCHY_INSTALL=~/.local/share/omarchy/install
JOURNAL_TAG="omarchy-install"

# ==============================================================================
# TERMINAL SETUP
# ==============================================================================
# Get terminal width - try multiple methods for Cage compatibility
if [[ -n "$COLUMNS" ]]; then
  TERM_WIDTH=$COLUMNS
elif command -v tput >/dev/null 2>&1; then
  TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
else
  TERM_WIDTH=80
fi

LOGO_WIDTH=86

# Calculate indent to align prompts and logs to the left edge of the "O"
LOGO_INDENT=$(((TERM_WIDTH - LOGO_WIDTH) / 2))
LOGO_INDENT=$((LOGO_INDENT < 0 ? 0 : LOGO_INDENT)) # Ensure non-negative

# ==============================================================================
# DISPLAY FUNCTIONS
# ==============================================================================

# show_logo [animation] [frame-rate]
show_logo() {
  clear
  echo -e "\n\n\n\n"
  if command -v tte &>/dev/null; then
    tte --anchor-text n --canvas-width 0 -i ~/.local/share/omarchy/logo.txt --frame-rate ${2:-120} ${1:-expand}
  else
    cat ~/.local/share/omarchy/logo.txt # TODO: Maybe get rid of this fallback?
  fi
}

show_subtext() {
  echo -e "\n\n"
  # Calculate centered position for subtext
  local text_length=${#1}
  local subtext_indent=$(((TERM_WIDTH - text_length) / 2))
  subtext_indent=$((subtext_indent < 0 ? 0 : subtext_indent))

  if command -v tte &>/dev/null; then
    printf "%*s%s\n" $subtext_indent "" "$1" | tte --frame-rate ${3:-640} ${2:-wipe}
  else
    printf "%*s%s\n" $subtext_indent "" "$1" # TODO: Maybe get rid of this fallback?
  fi
  echo
}

# Cleanup on exit
cleanup() {
  # Kill any active progress monitor
  [[ -n "${step_progress_pid:-}" ]] && kill $step_progress_pid 2>/dev/null || true
  # Kill sudo keeper
  [[ -n "$SUDO_PID" ]] && kill $SUDO_PID 2>/dev/null || true
  # Show cursor again
  printf "\033[?25h"
}
trap cleanup EXIT INT TERM

catch_errors() {
  local exit_code=$?
  local line_number=${BASH_LINENO[0]}

  cleanup

  show_logo crumble 120
  echo -e "\n\e[31mOmarchy installation failed!\e[0m"
  echo -e ""
  echo -e "You can retry by running: bash ~/.local/share/omarchy/install.sh"
  echo "Get help from the community: https://discord.gg/tXFUdasqhY"
  echo -e ""
  echo "View full logs with: journalctl -t omarchy-install"
  echo -e ""
  echo "Error occurred at line $line_number with exit code $exit_code"
  echo "Last command: ${BASH_COMMAND}"
  echo -e ""
  echo -e "Log tail:"

  journalctl -t "$JOURNAL_TAG" -n 20 --no-pager

  echo "Press Enter to exit..."
  read -n 1 -s -r </dev/tty
  exit 1
}
trap catch_errors ERR INT

# ==============================================================================
# MAIN EXECUTION FUNCTION
# ==============================================================================
install_step() {
  local step_title="$1"
  local script_cmd="$2"
  local script_name="$3"
  local start_time=$(date +%s)

  echo "Starting: $step_title" | systemd-cat -t "$JOURNAL_TAG" -p info

  if [[ "$script_name" != "system-updates.sh" ]]; then
    # Hide cursor during log display
    printf "\033[?25l"

    # Start a background process to show tail output
    (
      trap 'exit 0' TERM INT
      while true; do
        # Restore cursor to saved position
        printf "\033[u"

        # Get last 10 lines and print them
        journalctl -t "$JOURNAL_TAG" -n $PROGRESS_LINES --no-pager --output=cat 2>/dev/null |
          while IFS= read -r line; do
            # Clean and truncate line
            clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*[mGKH]//g' | sed 's/\r//g' | cut -c1-$((LOGO_WIDTH - 8)))
            # Clear current line and print
            printf "\033[2K%*s\033[90m  → %s\033[0m\n" $LOGO_INDENT "" "$clean_line"
          done

        # Clear any remaining lines if we have fewer than 10 entries
        lines_printed=$(journalctl -t "$JOURNAL_TAG" -n $PROGRESS_LINES --no-pager --output=cat 2>/dev/null | wc -l)
        for ((i = lines_printed; i < $PROGRESS_LINES; i++)); do
          printf "\033[2K\n"
        done

        sleep 0.2
      done
    ) &
    step_progress_pid=$!
  else
    # For system-updates.sh, just show a static message
    #
    # Sometimes, during this phase the binaries we need become unavailable and show errors
    # to the user that could be confusing.
    printf "%*s\033[90mLogs aren't shown during this step...this could take a bit.\033[0m\n" $LOGO_INDENT ""
  fi

  $script_cmd 2>&1 | systemd-cat -t "$JOURNAL_TAG" -p info
  local exit_code=${PIPESTATUS[0]}

  # Stop the step's progress display if it exists
  if [[ -n "${step_progress_pid:-}" ]]; then
    kill $step_progress_pid 2>/dev/null || true
    wait $step_progress_pid 2>/dev/null || true
    unset step_progress_pid
    # Show cursor again
    printf "\033[?25h"
  fi

  if [[ $exit_code -ne 0 ]]; then
    echo "Failed: $step_title" | systemd-cat -t "$JOURNAL_TAG" -p err
    false # This triggers the error trap
  fi

  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  echo "Completed: $step_title (${duration}s)" | systemd-cat -t "$JOURNAL_TAG" -p info
}

# ==============================================================================
# INITIAL SETUP - User interaction before spinner steps
# ==============================================================================
show_logo "waves" 240
show_subtext "Let's get some things out of the way..."

printf "%*sOmarchy installer requires administrator privileges.\n" $LOGO_INDENT ""
echo

for attempt in 1 2 3; do
  SUDO_PASS=$(gum input --password --no-show-help --placeholder "Enter your password" --prompt "$(printf "%*s[sudo] Password> " $LOGO_INDENT "")")
  if printf '%s\n' "$SUDO_PASS" | sudo -S true 2>/dev/null; then
    sudo -v
    unset SUDO_PASS
    printf "%*sSudo confirmed.\n" $LOGO_INDENT ""
    break
  else
    unset SUDO_PASS
    if [[ $attempt -lt 3 ]]; then
      printf "%*sSorry, incorrect password. Try again.\n" $LOGO_INDENT ""
    else
      printf "%*sSorry, 3 incorrect password attempts.\n" $LOGO_INDENT ""
      echo "Authentication failed - exiting installer" | systemd-cat -t "$JOURNAL_TAG" -p err
      exit 1
    fi
  fi
done

# Keep sudo alive in the background
(while true; do
  sudo -n true
  sleep 50
done 2>/dev/null) &
SUDO_PID=$!

printf "\n\n"
printf "%*sPlease provide your information for Git configuration:\n" $LOGO_INDENT ""
echo
export OMARCHY_USER_NAME=$(gum input --no-show-help --placeholder "Enter full name" --prompt "$(printf "%*sName> " $LOGO_INDENT "")")
export OMARCHY_USER_EMAIL=$(gum input --no-show-help --placeholder "Enter your email" --prompt "$(printf "%*sEmail> " $LOGO_INDENT "")")

# ==============================================================================
# INSTALLATION STEPS
# ==============================================================================

# Define the installation sections with their display info
declare -A SECTIONS=(
  ["config"]="beams|240|Let's install Omarchy! [1/5]"
  ["development"]="decrypt|920|Installing terminal tools [2/5]"
  ["desktop"]="slice|60|Installing desktop tools [3/5]"
  ["apps"]="expand|120|Installing default applications [4/5]"
  ["post_install"]="highlight|120|Updating system packages [5/5]"
)

# Order of sections to process
SECTION_ORDER=("config" "development" "desktop" "apps" "post_install")

for section in "${SECTION_ORDER[@]}"; do
  IFS='|' read -r animation speed subtitle <<<"${SECTIONS[$section]}"

  # Show section header
  show_logo "$animation" "$speed"
  show_subtext "$subtitle"

  # Save cursor position once for this section
  printf "\033[s"

  # Find and execute all .sh files in this section's directory
  if [[ -d "$OMARCHY_INSTALL/$section" ]]; then
    while IFS= read -r script; do
      script_name=$(basename "$script")
      step_title="${section^}: $script_name"

      if [[ "$TEST_MODE" == "true" ]]; then
        install_step "$step_title" "$HOME/.local/share/omarchy/test-task.sh" "$script_name"
      else
        install_step "$step_title" "bash $script" "$script_name"
      fi

    done < <(find "$OMARCHY_INSTALL/$section" -name "*.sh" -type f | sort)
  fi
done

# Reboot
show_logo laseretch 920
show_subtext "You're done! So we'll be rebooting now..."
sleep 2

if [[ "$TEST_MODE" != "true" ]]; then
  sudo reboot
fi
