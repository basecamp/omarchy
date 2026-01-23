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

  # Detect ARM bare metal hardware (Pi, Pine64, Rock64, BeagleBone, etc.)
  # All ARM SBCs have device tree model files; VMs typically don't
  # This prevents false positives from systemd-detect-virt on real hardware
  if [[ -f /sys/firmware/devicetree/base/model ]]; then
    export OMARCHY_ARM_BARE_METAL=true
  fi
fi

# Detect virtualization
if command -v systemd-detect-virt &>/dev/null; then
  virt_type=$(systemd-detect-virt || echo "none")

  # Set universal virtualization flag for any VM
  # Exception: ARM bare metal (Asahi, Pi, other SBCs) triggers false positives in systemd-detect-virt
  if [[ "$virt_type" != "none" ]] && [[ -z "$OMARCHY_ARM_BARE_METAL" ]]; then
    export OMARCHY_VIRTUALIZATION=true
  fi

  # Detect VMware specifically
  if [[ "$virt_type" == "vmware" ]]; then
    export OMARCHY_VMWARE=true
    export OMARCHY_SKIP_LIMINE=true
  fi

  # Enable software rendering for any VM except Parallels (which has good GPU virtualization)
  # ARM bare metal has real GPUs, don't force software rendering
  if [[ "$virt_type" != "none" && "$virt_type" != "parallels" ]] && [[ -z "$OMARCHY_ARM_BARE_METAL" ]]; then
    export OMARCHY_VM_SOFTWARE_RENDERING=true
  fi
fi

# Suppress gum help text on ARM/Asahi/VMs (Unicode doesn't render properly in raw TTY)
if [[ -n "$OMARCHY_ARM" ]] || [[ -n "$ASAHI_ALARM" ]] || [[ -n "$OMARCHY_VIRTUALIZATION" ]]; then
  export GUM_CONFIRM_SHOW_HELP=false
  export GUM_CHOOSE_SHOW_HELP=false
fi

# SKIP_ALL sets all skip flags except SKIP_YARU (for faster testing)
if [[ -n "${SKIP_ALL:-}" ]]; then
  export SKIP_OBS=true
  export SKIP_PINTA=true
  export SKIP_GHOSTTY=true
  export SKIP_SIGNAL_DESKTOP_BETA=true
fi

# Install
source "$OMARCHY_INSTALL/helpers/all.sh"
source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
source "$OMARCHY_INSTALL/login/all.sh"
source "$OMARCHY_INSTALL/virtualization/all.sh"
source "$OMARCHY_INSTALL/post-install/all.sh"
