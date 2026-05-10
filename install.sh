#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Define Omarchy locations
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
export PATH="$OMARCHY_PATH/bin:$PATH"

# Pre-flight validation for overlay/dualboot
if [[ "${OMARCHY_INSTALL_MODE:-fresh}" != "fresh" ]]; then
    echo "Running pre-flight validation for $OMARCHY_INSTALL_MODE mode..."
    
    available=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
    min_space=10
    [[ "$OMARCHY_INSTALL_MODE" == "dualboot" ]] && min_space=20
    
    if (( available < min_space )); then
        echo "ERROR: Insufficient disk space: ${available}GB available, ${min_space}GB minimum"
        exit 1
    fi
    
    if mount | grep -q "/dev/mapper/luks"; then
        echo "WARNING: Encrypted root detected - some features may have limitations"
    fi
    
    echo "Pre-flight validation passed"
fi

# Install
source "$OMARCHY_INSTALL/helpers/all.sh"
source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
source "$OMARCHY_INSTALL/login/all.sh"
source "$OMARCHY_INSTALL/post-install/all.sh"
