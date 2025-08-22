#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

export PATH="$HOME/.local/share/omarchy/bin:$PATH"
OMARCHY_INSTALL=~/.local/share/omarchy/install

# Give people a chance to retry running the installation
catch_errors() {
  echo -e "\n\e[31mOmarchy installation failed!\e[0m"

  if [[ -n $OMARCHY_BARE ]]; then
    echo "You can retry by running: OMARCHY_BARE=true bash ~/.local/share/omarchy/install.sh"
  else
    echo "You can retry by running: bash ~/.local/share/omarchy/install.sh"
  fi

  echo "Get help from the community: https://discord.gg/tXFUdasqhY"
}

trap catch_errors ERR

show_logo() {
  clear
  tte -i ~/.local/share/omarchy/logo.txt --frame-rate ${2:-120} ${1:-expand}
  echo
}

show_subtext() {
  echo "$1" | tte --frame-rate ${3:-640} ${2:-wipe}
  echo
}

# Install prerequisites
source $OMARCHY_INSTALL/preflight/gum.sh
source $OMARCHY_INSTALL/preflight/guard.sh
source $OMARCHY_INSTALL/preflight/aur.sh
source $OMARCHY_INSTALL/preflight/tte.sh
source $OMARCHY_INSTALL/preflight/migrations.sh

# Configuration
show_logo beams 240
show_subtext "Let's install Omarchy! [1/5]"
source $OMARCHY_INSTALL/config/identification.sh
source $OMARCHY_INSTALL/config/config.sh
source $OMARCHY_INSTALL/config/detect-keyboard-layout.sh
source $OMARCHY_INSTALL/config/fix-fkeys.sh
source $OMARCHY_INSTALL/config/network.sh
source $OMARCHY_INSTALL/config/power.sh
source $OMARCHY_INSTALL/config/timezones.sh
source $OMARCHY_INSTALL/config/login.sh
source $OMARCHY_INSTALL/config/nvidia.sh
source $OMARCHY_INSTALL/config/increase-sudo-tries.sh

# Development
show_logo decrypt 920
show_subtext "Installing terminal tools [2/5]"
source $OMARCHY_INSTALL/development/terminal.sh
source $OMARCHY_INSTALL/development/development.sh
source $OMARCHY_INSTALL/development/nvim.sh
source $OMARCHY_INSTALL/development/ruby.sh
source $OMARCHY_INSTALL/development/docker.sh
source $OMARCHY_INSTALL/development/firewall.sh

# Desktop
show_logo slice 60
show_subtext "Installing desktop tools [3/5]"
source $OMARCHY_INSTALL/desktop/desktop.sh
source $OMARCHY_INSTALL/desktop/hyprlandia.sh
source $OMARCHY_INSTALL/desktop/theme.sh
source $OMARCHY_INSTALL/desktop/bluetooth.sh
source $OMARCHY_INSTALL/desktop/asdcontrol.sh
source $OMARCHY_INSTALL/desktop/fonts.sh
source $OMARCHY_INSTALL/desktop/printer.sh

# Apps
show_logo expand
show_subtext "Installing default applications [4/5]"
source $OMARCHY_INSTALL/apps/webapps.sh
source $OMARCHY_INSTALL/apps/xtras.sh
source $OMARCHY_INSTALL/apps/mimetypes.sh

# Updates
show_logo highlight
show_subtext "Updating system packages [5/5]"
sudo updatedb

# Update system packages if we have a network connection
if ping -c1 omarchy.org &>/dev/null; then
  yay -Syu --noconfirm --ignore uwsm
fi

# Reboot
show_logo laseretch 920
show_subtext "You're done! So we'll be rebooting now..."
sleep 2
reboot
