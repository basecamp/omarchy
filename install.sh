#!/bin/bash
set -eE

LOGFILE=~/.local/share/omarchy/omarchy-install.log
OMARCHY_INSTALL=~/.local/share/omarchy/install

# Create/clear log file
echo "Omarchy installation started at $(date)" >"$LOGFILE"

# Error handler for preflight
catch_preflight_errors() {
  echo -e "\n\e[31mOmarchy preflight failed!\e[0m"
  echo "Check the log at: $LOGFILE"
  tail -n 20 $LOGFILE
  exit 1
}
trap catch_preflight_errors ERR

echo "Running preflight items..."

# Find and execute all .sh files in the preflight directory
if [[ -d "$OMARCHY_INSTALL/preflight" ]]; then
  while IFS= read -r script; do
    script_name=$(basename "$script")
    echo "Starting: Running preflight/$script_name..." | tee -a "$LOGFILE"
    bash "$script" >>"$LOGFILE" 2>&1
    echo "Completed: Running preflight/$script_name..." | tee -a "$LOGFILE"
  done < <(find "$OMARCHY_INSTALL/preflight" -name "*.sh" -type f | sort)
fi

echo -e "\n"

# Collect user identification before launching Cage
echo "Please provide your information for Git configuration:"
echo
export OMARCHY_USER_NAME=$(gum input --placeholder "Enter full name" --prompt "Name> ")
export OMARCHY_USER_EMAIL=$(gum input --placeholder "Enter email address" --prompt "Email> ")

echo -e "\nPreflight completed. Launching installer...\n"

# Adjust font size based on detected resolution
FONT_SIZE=12 # Default
if [[ -r /sys/class/graphics/fb0/virtual_size ]]; then
  IFS=',' read -r WIDTH HEIGHT </sys/class/graphics/fb0/virtual_size
  if [[ $HEIGHT -ge 1440 ]]; then
    FONT_SIZE=16
  elif [[ $HEIGHT -ge 2160 ]]; then
    FONT_SIZE=18
  fi
fi

# Pass TEST_MODE if set (can be set when calling this script: TEST_MODE=true ./install-cage.sh)
TEST_MODE="${TEST_MODE:-false}"

# Launch the main installer in cage with adjusted font size and environment variables
MAIN_INSTALLER="${OMARCHY_INSTALL%/install}/install-main.sh"
OMARCHY_USER_NAME="$OMARCHY_USER_NAME" OMARCHY_USER_EMAIL="$OMARCHY_USER_EMAIL" TEST_MODE="$TEST_MODE" \
  cage -- alacritty -o font.size=$FONT_SIZE -o 'font.normal.family="CaskaydiaMono Nerd Font"' -e bash "$MAIN_INSTALLER" 2>>"$LOGFILE"
