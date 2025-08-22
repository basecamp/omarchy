#!/bin/bash

# Exit immediately if a command exits with a non-zero status
# set -e

export PATH="$HOME/.local/share/omarchy/bin:$PATH"
OMARCHY_INSTALL=~/.local/share/omarchy/install

# Give people a chance to retry running the installation
catch_errors() {
  echo -e "\n\e[31mOmarchy installation failed!\e[0m"
  echo "The failing command was: \`$BASH_COMMAND\` (exit code: $?)"
  echo "See your installation log: ~/.local/state/omarchy/installation.log"
  echo
  echo "Get help from the community (or scan QR code below): https://discord.gg/tXFUdasqhY"
  echo "                                 "
  echo "    █▀▀▀▀▀█ ▄ ▄ ▀▄▄▄█ █▀▀▀▀▀█    "
  echo "    █ ███ █ ▄▄▄▄▀▄▀▄▀ █ ███ █    "
  echo "    █ ▀▀▀ █ ▄█  ▄█▄▄▀ █ ▀▀▀ █    "
  echo "    ▀▀▀▀▀▀▀ ▀▄█ █ █ █ ▀▀▀▀▀▀▀    "
  echo "    ▀▀█▀▀▄▀▀▀▀▄█▀▀█  ▀ █ ▀ █     "
  echo "    █▄█ ▄▄▀▄▄ ▀ ▄ ▀█▄▄▄▄ ▀ ▀█    "
  echo "    ▄ ▄▀█ ▀▄▀▀▀▄ ▄█▀▄█▀▄▀▄▀█▀    "
  echo "    █ ▄▄█▄▀▄█ ▄▄▄  ▀ ▄▀██▀ ▀█    "
  echo "    ▀ ▀   ▀ █ ▀▄  ▀▀█▀▀▀█▄▀      "
  echo "    █▀▀▀▀▀█ ▀█  ▄▀▀ █ ▀ █▄▀██    "
  echo "    █ ███ █ █▀▄▄▀ █▀███▀█▄██▄    "
  echo "    █ ▀▀▀ █ ██  ▀ █▄█ ▄▄▄█▀ █    "
  echo "    ▀▀▀▀▀▀▀ ▀ ▀ ▀▀▀  ▀ ▀▀▀▀▀▀    "
  echo "                                 "

  if [[ -n $OMARCHY_BARE ]]; then
    echo "You can retry by running: OMARCHY_BARE=true bash ~/.local/share/omarchy/install.sh"
  else
    echo "You can retry by running: bash ~/.local/share/omarchy/install.sh"
  fi
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

# Start logging
source $OMARCHY_INSTALL/log/before-install.sh

# Install prerequisites
source $OMARCHY_INSTALL/preflight/chroot.sh
source $OMARCHY_INSTALL/preflight/mirrorlist.sh
source $OMARCHY_INSTALL/preflight/gum.sh
source $OMARCHY_INSTALL/preflight/guard.sh
source $OMARCHY_INSTALL/preflight/aur.sh
source $OMARCHY_INSTALL/preflight/tte.sh
source $OMARCHY_INSTALL/preflight/migrations.sh

# Configuration
show_logo beams 240
show_subtext "Let's install Omarchy!"
source $OMARCHY_INSTALL/config/identification.sh
source $OMARCHY_INSTALL/config/config.sh
source $OMARCHY_INSTALL/config/detect-keyboard-layout.sh
source $OMARCHY_INSTALL/config/fix-fkeys.sh
source $OMARCHY_INSTALL/config/network.sh
source $OMARCHY_INSTALL/config/power.sh
source $OMARCHY_INSTALL/config/usb-autosuspend.sh
source $OMARCHY_INSTALL/config/timezones.sh
source $OMARCHY_INSTALL/config/login.sh
source $OMARCHY_INSTALL/config/nvidia.sh
source $OMARCHY_INSTALL/config/increase-sudo-tries.sh
source $OMARCHY_INSTALL/config/ignore-power-button.sh

# Development
source $OMARCHY_INSTALL/development/terminal.sh
source $OMARCHY_INSTALL/development/development.sh
source $OMARCHY_INSTALL/development/nvim.sh
source $OMARCHY_INSTALL/development/ruby.sh
source $OMARCHY_INSTALL/development/docker.sh
source $OMARCHY_INSTALL/development/firewall.sh

# Desktop
source $OMARCHY_INSTALL/desktop/desktop.sh
source $OMARCHY_INSTALL/desktop/hyprlandia.sh
source $OMARCHY_INSTALL/desktop/theme.sh
source $OMARCHY_INSTALL/desktop/bluetooth.sh
source $OMARCHY_INSTALL/desktop/asdcontrol.sh
source $OMARCHY_INSTALL/desktop/fonts.sh
source $OMARCHY_INSTALL/desktop/printer.sh

# Apps
source $OMARCHY_INSTALL/apps/webapps.sh
source $OMARCHY_INSTALL/apps/xtras.sh
source $OMARCHY_INSTALL/apps/mimetypes.sh

# Updates
sudo updatedb

# Update system packages if we have a network connection
if ping -c5 omarchy.org &>/dev/null; then
  yay -Syu --noconfirm
fi

# Stop logging
source $OMARCHY_INSTALL/log/after-install.sh

# Reboot
show_logo laseretch 920
show_subtext "You're done! So we're ready to reboot now..."

if sudo test -f /etc/sudoers.d/99-omarchy-installer; then
  sudo rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null
  gum confirm "Have you unplugged the USB installer?"
fi

sleep 2
reboot
