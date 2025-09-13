#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

export OMARCHY_PATH="$HOME/.local/share/omarchy"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
export PATH="$OMARCHY_PATH/bin:$PATH"

# Save original stdout and stderr for trap to use
exec 3>&1 4>&2

# Helpers
source $OMARCHY_INSTALL/helpers/chroot.sh
source $OMARCHY_INSTALL/helpers/logo.sh
source $OMARCHY_INSTALL/helpers/run-logged.sh
source $OMARCHY_INSTALL/helpers/trap-errors.sh
source $OMARCHY_INSTALL/helpers/tail-log-output.sh

# ENV Setup + Precheck
source $OMARCHY_INSTALL/preflight/set-size-vars.sh
source $OMARCHY_INSTALL/preflight/set-gum-styling.sh
source $OMARCHY_INSTALL/preflight/guard.sh # Need to be able to prompt
source $OMARCHY_INSTALL/preflight/start-logs.sh

clear_logo

gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "Installing Omarchy..."

start_log_output

# Preparation
run_logged $OMARCHY_INSTALL/preflight/show-env.sh
run_logged $OMARCHY_INSTALL/preflight/pacman.sh
run_logged $OMARCHY_INSTALL/preflight/migrations.sh
run_logged $OMARCHY_INSTALL/preflight/first-run-mode.sh
run_logged $OMARCHY_INSTALL/preflight/disable-mkinitcpio.sh

# Packages
run_logged $OMARCHY_INSTALL/packages.sh
run_logged $OMARCHY_INSTALL/packaging/fonts.sh
run_logged $OMARCHY_INSTALL/packaging/lazyvim.sh
run_logged $OMARCHY_INSTALL/packaging/icons.sh
run_logged $OMARCHY_INSTALL/packaging/webapps.sh
run_logged $OMARCHY_INSTALL/packaging/tuis.sh

# Configs
run_logged $OMARCHY_INSTALL/config/config.sh
run_logged $OMARCHY_INSTALL/config/theme.sh
run_logged $OMARCHY_INSTALL/config/branding.sh
run_logged $OMARCHY_INSTALL/config/git.sh
run_logged $OMARCHY_INSTALL/config/gpg.sh
run_logged $OMARCHY_INSTALL/config/timezones.sh
run_logged $OMARCHY_INSTALL/config/increase-sudo-tries.sh
run_logged $OMARCHY_INSTALL/config/increase-lockout-limit.sh
run_logged $OMARCHY_INSTALL/config/ssh-flakiness.sh
run_logged $OMARCHY_INSTALL/config/detect-keyboard-layout.sh
run_logged $OMARCHY_INSTALL/config/xcompose.sh
run_logged $OMARCHY_INSTALL/config/mise-ruby.sh
run_logged $OMARCHY_INSTALL/config/docker.sh
run_logged $OMARCHY_INSTALL/config/mimetypes.sh
run_logged $OMARCHY_INSTALL/config/localdb.sh
run_logged $OMARCHY_INSTALL/config/sudoless-asdcontrol.sh
run_logged $OMARCHY_INSTALL/config/hardware/network.sh
run_logged $OMARCHY_INSTALL/config/hardware/set-wireless-regdom.sh
run_logged $OMARCHY_INSTALL/config/hardware/fix-fkeys.sh
run_logged $OMARCHY_INSTALL/config/hardware/bluetooth.sh
run_logged $OMARCHY_INSTALL/config/hardware/printer.sh
run_logged $OMARCHY_INSTALL/config/hardware/usb-autosuspend.sh
run_logged $OMARCHY_INSTALL/config/hardware/ignore-power-button.sh
run_logged $OMARCHY_INSTALL/config/hardware/nvidia.sh
run_logged $OMARCHY_INSTALL/config/hardware/fix-f13-amd-audio-input.sh
run_logged $OMARCHY_INSTALL/config/hardware/fix-apple-bcm4360.sh
run_logged $OMARCHY_INSTALL/config/hardware/fix-apple-t1-mbp.sh

# Login
run_logged $OMARCHY_INSTALL/login/plymouth.sh
run_logged $OMARCHY_INSTALL/login/limine-snapper.sh
run_logged $OMARCHY_INSTALL/login/enable-mkinitcpio.sh
run_logged $OMARCHY_INSTALL/login/alt-bootloaders.sh

# Post-install
run_logged $OMARCHY_INSTALL/post-install/pacman.sh
source $OMARCHY_INSTALL/post-install/stop-logs.sh
source $OMARCHY_INSTALL/reboot.sh
