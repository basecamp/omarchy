#!/bin/bash
set -e

export PATH="$HOME/.local/share/zyro/bin:$PATH"
ZYRO_INSTALL=~/.local/share/zyro/install

# Give people a chance to retry running the installation
catch_errors() {
  echo -e "\n\e[31mInstallation failed!\e[0m"
  echo "You can retry by running: bash ~/.local/share/zyro/install.sh"
}

trap catch_errors ERR

show_logo() {
  clear
  # tte -i ~/.local/share/zyro/logo.txt --frame-rate ${2:-120} ${1:-expand}
  cat <~/.local/share/zyro/logo.txt
  echo
}

show_subtext() {
  echo "$1" # | tte --frame-rate ${3:-640} ${2:-wipe}
  echo
}

# Install prerequisites

source $ZYRO_INSTALL/preflight/guard.sh
source $ZYRO_INSTALL/preflight/aur.sh
source $ZYRO_INSTALL/preflight/presentation.sh
source $ZYRO_INSTALL/preflight/migrations.sh

# Configuration
show_logo beams 240
show_subtext "Let's install Zyro! [1/5]"
source $ZYRO_INSTALL/config/identification.sh
source $ZYRO_INSTALL/config/config.sh
source $ZYRO_INSTALL/config/detect-keyboard-layout.sh
source $ZYRO_INSTALL/config/fix-fkeys.sh
source $ZYRO_INSTALL/config/network.sh
source $ZYRO_INSTALL/config/power.sh
source $ZYRO_INSTALL/config/timezones.sh
source $ZYRO_INSTALL/config/login.sh
source $ZYRO_INSTALL/config/nvidia.sh

# Development
show_logo decrypt 920
show_subtext "Installing terminal tools [2/5]"
source $ZYRO_INSTALL/development/terminal.sh
source $ZYRO_INSTALL/development/development.sh
source $ZYRO_INSTALL/development/nvim.sh
source $ZYRO_INSTALL/development/ruby.sh
source $ZYRO_INSTALL/development/docker.sh
source $ZYRO_INSTALL/development/firewall.sh

# Desktop
show_logo slice 60
show_subtext "Installing desktop tools [3/5]"
source $ZYRO_INSTALL/desktop/desktop.sh
source $ZYRO_INSTALL/desktop/hyprlandia.sh
source $ZYRO_INSTALL/desktop/theme.sh
source $ZYRO_INSTALL/desktop/bluetooth.sh
source $ZYRO_INSTALL/desktop/asdcontrol.sh
source $ZYRO_INSTALL/desktop/fonts.sh
source $ZYRO_INSTALL/desktop/printer.sh

# Apps
show_logo expand
show_subtext "Installing default applications [4/5]"
source $ZYRO_INSTALL/apps/webapps.sh
source $ZYRO_INSTALL/apps/xtras.sh
source $ZYRO_INSTALL/apps/mimetypes.sh

# Updates
show_logo highlight
show_subtext "Updating system packages [5/5]"
sudo updatedb
yay -Syu --noconfirm --ignore uwsm

# Reboot
show_logo laseretch 920
show_subtext "You're done! So we'll be rebooting now..."
sleep 2
# reboot
