#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Define Omarchy locations
export OMARCHY_PATH="/usr/share/omarchy"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"

# Load helpers
source "$OMARCHY_INSTALL/helpers/chroot.sh"

# Simple script runner that outputs to stdout/stderr
# archinstall captures all output in /var/log/archinstall/install.log
run_logged() {
  local script="$1"
  local script_name=$(basename "$script")
  
  echo "Running: $script_name"
  
  source "$script"
  local exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    echo "✓ Completed: $script_name"
    echo
  else
    echo "✗ Failed: $script_name (exit code: $exit_code)"
    return $exit_code
  fi
}

# Run installation phases
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
source "$OMARCHY_INSTALL/login/all.sh"
source "$OMARCHY_INSTALL/post-install/all.sh"
