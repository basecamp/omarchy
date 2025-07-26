#!/bin/bash
set -eE

LOGFILE=~/omarchy-install.log

# Create/clear log file
echo "Omarchy installation started at $(date)" >"$LOGFILE"

# Request sudo access upfront
echo "Omarchy installation requires administrator access."
echo "Please enter your password when prompted:"
sudo -v

# Keep sudo alive in the background
(while true; do
  sudo -n true
  sleep 60
done) &
SUDO_PID=$!

# Track progress PIDs globally
PROGRESS_PIDS=()

# Kill the sudo refresh and any progress monitors on exit
cleanup() {
  kill $SUDO_PID 2>/dev/null || true
  for pid in "${PROGRESS_PIDS[@]}"; do
    kill $pid 2>/dev/null || true
  done
}
trap cleanup EXIT

# OMARCHY_INSTALL=~/.local/share/omarchy/install
OMARCHY_INSTALL=~/Dev/omarchy/install

catch_errors() {
  # Kill all progress monitors immediately
  for pid in "${PROGRESS_PIDS[@]}"; do
    kill $pid 2>/dev/null || true
  done
  # Clear any progress line that might be showing
  printf "\033[1B\r\033[K\033[1A"
  echo -e "\n\e[31mOmarchy installation failed!\e[0m"
  echo "You can retry by running: bash ~/.local/share/omarchy/install.sh"
  echo "Get help from the community: https://discord.gg/tXFUdasqhY"
  tail -n 20 $LOGFILE
}
trap catch_errors ERR

show_logo() {
  clear
  if command -v tte &>/dev/null; then
    tte -i ~/.local/share/omarchy/logo.txt --frame-rate ${2:-120} ${1:-expand}
  else
    cat ~/.local/share/omarchy/logo.txt
  fi
  echo
}

show_subtext() {
  if command -v tte &>/dev/null; then
    echo "$1" | tte --frame-rate ${3:-640} ${2:-wipe}
  else
    echo "$1"
  fi
  echo
}

spinner_step() {
  local step_title="$1"
  local script_path="$2"

  # Log the start
  echo "Starting: $step_title" >>"$LOGFILE"

  # Check if script exists
  if [[ ! -f "$OMARCHY_INSTALL/$script_path" ]]; then
    echo "Warning: Script not found: $OMARCHY_INSTALL/$script_path" | tee -a "$LOGFILE"
    return
  fi

  # Start a background process to show progress
  (
    # Give the script a moment to start
    sleep 0.5
    while true; do
      # Clear line and show last log entry
      last_line=$(tail -n 50 "$LOGFILE" 2>/dev/null | grep -v "^$" | grep -v "^Starting:" | grep -v "^Completed:" | tail -n 1 | cut -c1-80)
      if [[ -n "$last_line" ]]; then
        printf "\033[s\033[1B\r\033[K\033[90m  → %s\033[0m\033[u" "$last_line"
      fi
      sleep 0.3
    done
  ) &
  local progress_pid=$!
  PROGRESS_PIDS+=($progress_pid)

  # Run script with spinner, output goes to log
  gum spin --spinner line --title "$step_title" -- bash -c "
    bash '$OMARCHY_INSTALL/$script_path' >>'$LOGFILE' 2>&1
  "
  local exit_code=$?

  # Stop progress display
  kill $progress_pid 2>/dev/null || true

  # Clear any remaining progress line
  printf "\033[1B\r\033[K\033[1A"

  # Check if command failed
  if [[ $exit_code -ne 0 ]]; then
    echo "Failed: $step_title" >>"$LOGFILE"
    false # This will trigger the trap
  fi

  # Log completion
  echo "Completed: $step_title" >>"$LOGFILE"
}

# Install prerequisites
spinner_step "Running preflight/aur.sh..." "preflight/aur.sh"
spinner_step "Running preflight/presentation.sh..." "preflight/presentation.sh"

# Configuration
show_logo beams 240
show_subtext "Let's install Omarchy! [1/5]"
spinner_step "Updating packages" "preflight/update.sh"
spinner_step "Config: config.sh" "config/config.sh"
spinner_step "Config: detect-keyboard-layout.sh" "config/detect-keyboard-layout.sh"
spinner_step "Config: fix-fkeys.sh" "config/fix-fkeys.sh"
spinner_step "Config: network.sh" "config/network.sh"
spinner_step "Config: power.sh" "config/power.sh"
spinner_step "Config: login.sh" "config/login.sh"
spinner_step "Config: plymouth.sh" "config/plymouth.sh"
spinner_step "Config: nvidia.sh" "config/nvidia.sh"

# Development
show_logo decrypt 920
show_subtext "Installing terminal tools [2/10]"
spinner_step "Development: terminal.sh" "development/terminal.sh"
spinner_step "Development: development.sh" "development/development.sh"
spinner_step "Development: nvim.sh" "development/nvim.sh"
spinner_step "Development: ruby.sh" "development/ruby.sh"
spinner_step "Development: docker.sh" "development/docker.sh"
spinner_step "Development: firewall.sh" "development/firewall.sh"

# Desktop
show_logo slice 60
show_subtext "Installing desktop tools [3/10]"
spinner_step "Desktop: desktop.sh" "desktop/desktop.sh"
spinner_step "Desktop: hyprlandia.sh" "desktop/hyprlandia.sh"
spinner_step "Desktop: theme.sh" "desktop/theme.sh"
spinner_step "Desktop: bluetooth.sh" "desktop/bluetooth.sh"
spinner_step "Desktop: asdcontrol.sh" "desktop/asdcontrol.sh"
spinner_step "Desktop: fonts.sh" "desktop/fonts.sh"
spinner_step "Desktop: printer.sh" "desktop/printer.sh"

# Apps
show_logo expand
show_subtext "Installing default applications [4/5]"
spinner_step "Apps: webapps.sh" "apps/webapps.sh"
spinner_step "Apps: xtras.sh" "apps/xtras.sh"
spinner_step "Apps: mimetypes.sh" "apps/mimetypes.sh"

# Updates
show_logo highlight
show_subtext "Updating system packages [5/5]"
spinner_step "Updating mlocate (updatedb)" "updates/updatedb.sh"
spinner_step "Pacman system update" "updates/pacman.sh"

# Reboot
show_logo laseretch 920
show_subtext "You're done! So we'll be rebooting now..."
spinner_step "Rebooting system" "updates/reboot.sh"
