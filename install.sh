#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Resolve real user home when running under sudo
if [[ -n "${SUDO_USER:-}" ]]; then
  REAL_HOME=$(eval echo "~$SUDO_USER")
else
  REAL_HOME="$HOME"
fi

# Define DedSec locations
export OMARCHY_PATH="$REAL_HOME/.local/share/omarchy"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
export PATH="$OMARCHY_PATH/bin:$PATH"

# Copy source tree into OMARCHY_PATH when running directly (not from boot.sh)
if [[ -z "${OMARCHY_ONLINE_INSTALL:-}" ]]; then
  SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$SOURCE_DIR" != "$OMARCHY_PATH" ]]; then
    echo -e "\e[32mDeploying DedSec from $SOURCE_DIR to $OMARCHY_PATH\e[0m"
    rm -rf "$OMARCHY_PATH"
    mkdir -p "$OMARCHY_PATH"
    cp -a "$SOURCE_DIR/." "$OMARCHY_PATH/"
    # Fix ownership when running under sudo
    if [[ -n "${SUDO_USER:-}" ]]; then
      chown -R "$SUDO_USER:$SUDO_USER" "$OMARCHY_PATH"
    fi
  fi
fi

# Deploy-only mode: just copy files, skip full install
if [[ "${1:-}" == "--deploy-only" || "${1:-}" == "-d" ]]; then
  echo -e "\e[32mDedSec deployed to $OMARCHY_PATH\e[0m"
  exit 0
fi

# Install
source "$OMARCHY_INSTALL/helpers/all.sh"
source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
source "$OMARCHY_INSTALL/login/all.sh"
source "$OMARCHY_INSTALL/post-install/all.sh"
