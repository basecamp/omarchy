#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eE

export PATH="$HOME/.local/share/omarchy/bin:$PATH"
OMARCHY_INSTALL=~/.local/share/omarchy/install

# Install prerequisites
source $OMARCHY_INSTALL/preflight/show-env.sh
source $OMARCHY_INSTALL/preflight/trap-errors.sh
source $OMARCHY_INSTALL/preflight/chroot.sh
source $OMARCHY_INSTALL/preflight/guard.sh
source $OMARCHY_INSTALL/preflight/repositories.sh
source $OMARCHY_INSTALL/preflight/migrations.sh
source $OMARCHY_INSTALL/preflight/first-run-mode.sh

# Packages
source $OMARCHY_INSTALL/packages.sh
source $OMARCHY_INSTALL/packaging/asdcontrol.sh
source $OMARCHY_INSTALL/packaging/fonts.sh
source $OMARCHY_INSTALL/packaging/lazyvim.sh

# Configuration
source $OMARCHY_INSTALL/config/config.sh
source $OMARCHY_INSTALL/config/theme.sh
source $OMARCHY_INSTALL/config/branding.sh
source $OMARCHY_INSTALL/config/network.sh
source $OMARCHY_INSTALL/config/git.sh
source $OMARCHY_INSTALL/config/gpg.sh
source $OMARCHY_INSTALL/config/usb-autosuspend.sh
source $OMARCHY_INSTALL/config/timezones.sh
source $OMARCHY_INSTALL/config/nvidia.sh
source $OMARCHY_INSTALL/config/increase-sudo-tries.sh
source $OMARCHY_INSTALL/config/increase-lockout-limit.sh
source $OMARCHY_INSTALL/config/ignore-power-button.sh
source $OMARCHY_INSTALL/config/ssh-flakiness.sh
source $OMARCHY_INSTALL/config/detect-keyboard-layout.sh
source $OMARCHY_INSTALL/config/fix-fkeys.sh
source $OMARCHY_INSTALL/config/bluetooth.sh
source $OMARCHY_INSTALL/config/printer.sh
source $OMARCHY_INSTALL/config/xcompose.sh
source $OMARCHY_INSTALL/config/mise-ruby.sh
source $OMARCHY_INSTALL/config/docker.sh

# Login
source $OMARCHY_INSTALL/login/plymouth.sh
source $OMARCHY_INSTALL/login/limine-snapper.sh
source $OMARCHY_INSTALL/login/alt-bootloaders.sh

# Apps
source $OMARCHY_INSTALL/apps/webapps.sh
source $OMARCHY_INSTALL/apps/tuis.sh
source $OMARCHY_INSTALL/apps/mimetypes.sh

# Updates
sudo updatedb

# Update system packages
sudo pacman -Syu --noconfirm

# Reboot
omarchy-show-logo
echo -e "\n\e[32mYou're done! So we're ready to reboot now...\e[0m"

if sudo test -f /etc/sudoers.d/99-omarchy-installer; then
  sudo rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null
  echo -e "\nRemember to remove USB installer!"
fi

sleep 5
reboot
