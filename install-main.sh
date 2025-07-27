#!/bin/bash
# Omarchy installation script - main installer that runs inside Cage
# Shows progress bar, spinner with live log output during installation
set -eE

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# TEST_MODE can be set via environment variable, defaults to false
TEST_MODE="${TEST_MODE:-false}"
PROGRESS_LINES=5 # Number of progress lines to show below spinner
PROGRESS_PIDS=()
LOGFILE=~/.local/share/omarchy/omarchy-install.log
OMARCHY_INSTALL=~/.local/share/omarchy/install

# Ensure log file exists and is writable
if [[ ! -f "$LOGFILE" ]]; then
  echo "Creating log file: $LOGFILE"
  touch "$LOGFILE"
fi

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

LOGO_WIDTH=88 # Width of the OMARCHY logo

# Calculate indent to center logo and align spinner with "O"
LOGO_INDENT=$(((TERM_WIDTH - LOGO_WIDTH) / 2))
LOGO_INDENT=$((LOGO_INDENT < 0 ? 0 : LOGO_INDENT)) # Ensure non-negative

# Progress tracking setup
TOTAL_STEPS=$(find "$OMARCHY_INSTALL" -name "*.sh" -type f ! -path "*/preflight/*" 2>/dev/null | wc -l)
CURRENT_STEP=0

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
  echo
  if command -v tte &>/dev/null; then
    # Add indent to the text before piping to tte
    printf "%*s%s\n" $LOGO_INDENT "" "$1" | tte --frame-rate ${3:-640} ${2:-wipe}
  else
    printf "%*s%s\n" $LOGO_INDENT "" "$1" # TODO: Maybe get rid of this fallback?
  fi
  echo
}

# Kill any progress monitors on exit
cleanup() {
  for pid in "${PROGRESS_PIDS[@]}"; do
    kill $pid 2>/dev/null || true
  done
  # Kill sudo keeper
  [[ -n "$SUDO_PID" ]] && kill $SUDO_PID 2>/dev/null || true
}
trap cleanup EXIT

catch_errors() {
  local exit_code=$?
  local line_number=${BASH_LINENO[0]}

  cleanup

  show_logo crumble 120
  echo -e "\n\e[31mOmarchy installation failed!\e[0m"
  echo -e ""
  echo -e "\nYou can retry by running: bash ~/.local/share/omarchy/install.sh"
  echo "Get help from the community: https://discord.gg/tXFUdasqhY"
  echo -e ""
  echo "Error occurred at line $line_number with exit code $exit_code"
  echo "Last command: ${BASH_COMMAND}"
  echo -e "\nLog tail:"

  tail -n 20 "$LOGFILE"

  echo "Press Enter to exit..."
  read -n 1 -s -r </dev/tty
  exit 1
}
trap catch_errors ERR

# ==============================================================================
# PROGRESS BAR
# ==============================================================================
show_progress_bar() {
  # Ensure we don't divide by zero
  if [[ $TOTAL_STEPS -eq 0 ]]; then
    return
  fi

  local percent=$((CURRENT_STEP / TOTAL_STEPS * 100))
  local bar_width=40
  local filled=$((bar_width * CURRENT_STEP / TOTAL_STEPS))
  local empty=$((bar_width - filled))

  # ASCII progress bar on its own line
  printf "%*s" $LOGO_INDENT ""
  printf "\033[90m["
  if [[ $filled -gt 0 ]]; then
    printf "\033[92m%${filled}s" | tr ' ' '='
  fi
  if [[ $empty -gt 0 ]]; then
    printf "\033[90m%${empty}s" | tr ' ' '-'
  fi
  printf "] \033[97m%d%%\033[0m  %d/%d steps" $percent $CURRENT_STEP $TOTAL_STEPS
}

# ==============================================================================
# MAIN EXECUTION FUNCTION
# ==============================================================================
spinner_step() {
  local step_title="$1"
  local script_cmd="$2"

  # Increment step counter
  CURRENT_STEP=$((CURRENT_STEP + 1))

  # Log the start
  echo "Starting: $step_title" >>"$LOGFILE" 2>&1

  # Move up to overwrite previous progress bar
  printf "\033[1A"

  show_progress_bar
  echo ""

  # Start a background process to show progress
  (
    sleep 0.2
    while true; do
      last_lines=$(tail -n $PROGRESS_LINES "$LOGFILE" | sed 's/\x1b\[[0-9;]*[mGKH]//g' | sed 's/\r//g')

      # Save cursor position
      printf "\033[s"

      # Print each line, clearing as we go
      line_num=1
      while IFS= read -r line; do
        if [[ -n "$line" ]] && [[ $line_num -le $PROGRESS_LINES ]]; then
          local max_width=$((LOGO_WIDTH - 8))
          # Ensure line is truncated to prevent wrapping
          local truncated_line=$(echo "$line" | cut -c1-${max_width})
          printf "\033[${line_num}B\033[2K\033[${LOGO_INDENT}C\033[90m  → %s\033[0m\033[u" "$truncated_line"
          line_num=$((line_num + 1))
        fi
      done <<<"$last_lines"

      sleep 0.2
    done
  ) &
  local progress_pid=$!
  PROGRESS_PIDS+=($progress_pid)

  # Add indent to the title
  local display_title=$(printf "%*s%s" $LOGO_INDENT "" "$step_title")

  # Run the command with spinner
  gum spin --spinner line --align right --title "$display_title" -- bash -c "
    $script_cmd >>'$LOGFILE' 2>&1
  "
  local exit_code=$?

  # Stop progress display
  kill $progress_pid 2>/dev/null || true

  # Check if command failed
  if [[ $exit_code -ne 0 ]]; then
    echo "Failed: $step_title" >>"$LOGFILE"
    false # This will trigger the trap
  fi

  echo "Completed: $step_title" >>"$LOGFILE"
}

# ==============================================================================
# INITIAL SETUP - User interaction before spinner steps
# ==============================================================================
show_logo "waves" 240
show_subtext "Let's get some things out of the way..."

# Request sudo upfront for the entire installation
printf "%*sOmarchy installer requires administrator privileges.\n" $LOGO_INDENT ""
echo

# Try up to 3 times for sudo password
for attempt in 1 2 3; do
  SUDO_PASS=$(gum input --password --no-show-help --placeholder "Enter your password" --prompt "$(printf "%*s[sudo] Password> " $LOGO_INDENT "")")
  # Use printf instead of echo to avoid issues with special characters
  if printf '%s\n' "$SUDO_PASS" | sudo -S true 2>/dev/null; then
    # Successfully authenticated, validate sudo access
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
      echo "Authentication failed - exiting installer" >>"$LOGFILE"
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

# Collect user identification before launching Cage
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

# Process each section
for section in "${SECTION_ORDER[@]}"; do
  # Parse section info
  IFS='|' read -r animation speed subtitle <<<"${SECTIONS[$section]}"

  # Show section header
  show_logo "$animation" "$speed"
  show_subtext "$subtitle"

  # Find and execute all .sh files in this section's directory
  if [[ -d "$OMARCHY_INSTALL/$section" ]]; then
    while IFS= read -r script; do
      script_name=$(basename "$script")
      step_title="${section^}: $script_name" # Capitalize first letter

      if [[ "$TEST_MODE" == "true" ]]; then
        spinner_step "$step_title" "~/.local/share/omarchy/test-task.sh '$step_title'"
      else
        spinner_step "$step_title" "bash $script"
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
