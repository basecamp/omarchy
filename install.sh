#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Define Omarchy locations
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"

# Generate timestamped log filename (only once per install session)
# Retries preserve timestamp, but fresh installs get new timestamp
if [[ -z "${OMARCHY_LOG_INSTALL_TIMESTAMP:-}" ]]; then
  export OMARCHY_LOG_INSTALL_TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
fi
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install-${OMARCHY_LOG_INSTALL_TIMESTAMP}.log"

export PATH="$OMARCHY_PATH/bin:$PATH"

# Detect ARM architecture early so preflight/pacman.sh configures correct mirrors
# This must be in the main shell since run_logged() executes scripts in subshells
arch=$(uname -m)
if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
  export OMARCHY_ARM=true

  # Detect Asahi Linux / Apple Silicon hardware (uses U-Boot, can't use Limine)
  # Check kernel name OR device tree for Apple hardware (newer kernels may not have "asahi" in name)
  if uname -r | grep -qi "asahi" || grep -q "apple" /sys/firmware/devicetree/base/compatible 2>/dev/null; then
    export ASAHI_ALARM=true
  fi
fi

# Detect virtualization
if command -v systemd-detect-virt &>/dev/null; then
  virt_type=$(systemd-detect-virt || echo "none")

  # Set universal virtualization flag for any VM
  # Exception: Asahi is always bare metal, even if systemd-detect-virt reports otherwise
  # (Apple Silicon can trigger false positives due to hypervisor-like characteristics)
  if [[ "$virt_type" != "none" ]] && [[ -z "$ASAHI_ALARM" ]]; then
    export OMARCHY_VIRTUALIZATION=true
  fi

  # Detect VMware specifically
  if [[ "$virt_type" == "vmware" ]]; then
    export OMARCHY_VMWARE=true
    export OMARCHY_SKIP_LIMINE=true
  fi

  # Enable software rendering for any VM except Parallels (which has good GPU virtualization)
  # Exception: Asahi is bare metal, don't enable software rendering
  if [[ "$virt_type" != "none" && "$virt_type" != "parallels" ]] && [[ -z "$ASAHI_ALARM" ]]; then
    export OMARCHY_VM_SOFTWARE_RENDERING=true
  fi
fi

# Suppress gum help text on ARM/Asahi/VMs (Unicode doesn't render properly in raw TTY)
if [[ -n "$OMARCHY_ARM" ]] || [[ -n "$ASAHI_ALARM" ]] || [[ -n "$OMARCHY_VIRTUALIZATION" ]]; then
  export GUM_CONFIRM_SHOW_HELP=false
  export GUM_CHOOSE_SHOW_HELP=false
fi

# Install
source "$OMARCHY_INSTALL/helpers/all.sh"
source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
source "$OMARCHY_INSTALL/login/all.sh"
source "$OMARCHY_INSTALL/virtualization/all.sh"
source "$OMARCHY_INSTALL/post-install/all.sh"
