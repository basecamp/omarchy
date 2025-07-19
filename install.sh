#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Give people a chance to retry running the installation
catch_errors() {
  echo -e "\n\e[31mOmarchy installation failed!\e[0m"
  echo "You can retry by running: bash ~/.local/share/omarchy/install.sh"
  echo "Get help from the community: https://discord.gg/tXFUdasqhY"
}

trap catch_errors ERR

# Install everything
for f in ~/.local/share/omarchy/install/*.sh; do
  echo -e "\nRunning installer: $f"
  source "$f"
done

# Ensure locate is up to date now that everything has been installed
sudo updatedb

gum confirm "Reboot to apply all settings?" && reboot
