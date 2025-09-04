#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eE

OMARCHY_PATH="$HOME/.local/share/omarchy"
OMARCHY_INSTALL="$OMARCHY_PATH/install"
export PATH="$OMARCHY_PATH/bin:$PATH"

# Preparation
source $OMARCHY_INSTALL/preflight/show-env.sh
source $OMARCHY_INSTALL/preflight/trap-errors.sh
source $OMARCHY_INSTALL/preflight/guard.sh
source $OMARCHY_INSTALL/preflight/chroot.sh
source $OMARCHY_INSTALL/preflight/pacman.sh
source $OMARCHY_INSTALL/preflight/migrations.sh
source $OMARCHY_INSTALL/preflight/first-run-mode.sh

# Packaging
source $OMARCHY_INSTALL/packages.sh
source $OMARCHY_INSTALL/packaging/fonts.sh
source $OMARCHY_INSTALL/packaging/webapps.sh
source $OMARCHY_INSTALL/packaging/tuis.sh

# Configuration
source $OMARCHY_INSTALL/config/config.sh
source $OMARCHY_INSTALL/config/theme.sh
source $OMARCHY_INSTALL/config/branding.sh
source $OMARCHY_INSTALL/config/git.sh
source $OMARCHY_INSTALL/config/gpg.sh
source $OMARCHY_INSTALL/config/timezones.sh
source $OMARCHY_INSTALL/config/increase-sudo-tries.sh
source $OMARCHY_INSTALL/config/increase-lockout-limit.sh
source $OMARCHY_INSTALL/config/ssh-flakiness.sh
source $OMARCHY_INSTALL/config/detect-keyboard-layout.sh
source $OMARCHY_INSTALL/config/xcompose.sh
source $OMARCHY_INSTALL/config/docker.sh
source $OMARCHY_INSTALL/config/mimetypes.sh
source $OMARCHY_INSTALL/config/localdb.sh
source $OMARCHY_INSTALL/config/sudoless-asdcontrol.sh
source $OMARCHY_INSTALL/config/hardware/network.sh
source $OMARCHY_INSTALL/config/hardware/fix-fkeys.sh
source $OMARCHY_INSTALL/config/hardware/bluetooth.sh
source $OMARCHY_INSTALL/config/hardware/printer.sh
source $OMARCHY_INSTALL/config/hardware/usb-autosuspend.sh
source $OMARCHY_INSTALL/config/hardware/ignore-power-button.sh
source $OMARCHY_INSTALL/config/hardware/nvidia.sh
source $OMARCHY_INSTALL/config/hardware/fix-f13-amd-audio-input.sh

# Login
source $OMARCHY_INSTALL/login/plymouth.sh
source $OMARCHY_INSTALL/login/limine-snapper.sh
source $OMARCHY_INSTALL/login/alt-bootloaders.sh

# Finishing
source $OMARCHY_INSTALL/reboot.sh
