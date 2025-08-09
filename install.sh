#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check if running as root and offer to create a user
check_root_user() {
  if [[ $EUID -eq 0 ]]; then
    echo -e "\e[33mWarning: This script should not be run as the root user!\e[0m"
    echo "Running as root can cause issues with makepkg and other tools."
    echo "This script should be run as a normal user with sudo permissions."
    echo
    echo "Would you like me to help create a new user account?"
    echo -n "Create a new user? [Y/n]: "
    read -r response
    
    if [[ -z "$response" || "$response" =~ ^[Yy]$ ]]; then
      create_new_user
    else
      echo "Please create a user manually and run this script as that user."
      echo "Example commands:"
      echo "  useradd -m -G wheel username"
      echo "  passwd username"
      echo "  su - username"
      exit 1
    fi
  fi
}

# Create a new user with sudo permissions
create_new_user() {
  echo
  echo "Creating a new user account..."
  
  # Get username
  while true; do
    echo -n "Enter username for the new user: "
    read -r username
    if [[ -n "$username" && "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
      if ! id "$username" &>/dev/null; then
        break
      else
        echo "User '$username' already exists. Please choose a different name."
      fi
    else
      echo "Invalid username. Use lowercase letters, numbers, underscore, and hyphen only."
    fi
  done
  
  # Create user with home directory and add to wheel group
  echo "Creating user '$username'..."
  useradd -m -G wheel "$username"
  
  # Set password
  echo "Please set a password for user '$username':"
  passwd "$username"
  
  # Ensure sudo is configured for wheel group
  if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    echo "Configuring sudo access for wheel group..."
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
  fi
  
  echo -e "\e[32mUser '$username' created successfully!\e[0m"
  echo "Please switch to the new user and run this script again:"
  echo "  su - $username"
  echo "  # Then re-run the installation command"
  exit 0
}

# Run root user check
check_root_user

# Check for required prerequisites
check_prerequisites() {
  local missing_deps=()
  
  # Check for git
  if ! command -v git >/dev/null 2>&1; then
    missing_deps+=("git")
  fi
  
  # Check for sudo
  if ! command -v sudo >/dev/null 2>&1; then
    missing_deps+=("sudo")
  fi
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    echo -e "\e[33mWarning: Missing required prerequisites!\e[0m"
    echo "The following commands are required but not found:"
    for dep in "${missing_deps[@]}"; do
      echo "  - $dep"
    done
    echo
    echo "Would you like to install the missing prerequisites now?"
    echo "Command to run: pacman -S ${missing_deps[*]}"
    echo -n "Install missing dependencies? [Y/n]: "
    read -r response
    
    # Default to yes if empty response
    if [[ -z "$response" || "$response" =~ ^[Yy]$ ]]; then
      echo "Installing missing dependencies..."
      if sudo pacman -S --noconfirm ${missing_deps[*]}; then
        echo -e "\e[32mDependencies installed successfully!\e[0m"
        echo "Continuing with installation..."
      else
        echo -e "\e[31mFailed to install dependencies!\e[0m"
        echo "Please install them manually and try again."
        exit 1
      fi
    else
      echo "Installation cancelled. Please install the missing prerequisites manually:"
      echo "  pacman -S ${missing_deps[*]}"
      exit 1
    fi
  fi
}

# Run prerequisite check
check_prerequisites

OMARCHY_INSTALL=~/.local/share/omarchy/install

# Give people a chance to retry running the installation
catch_errors() {
  echo -e "\n\e[31mOmarchy installation failed!\e[0m"
  echo "You can retry by running: bash ~/.local/share/omarchy/install.sh"
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
source $OMARCHY_INSTALL/preflight/aur.sh
source $OMARCHY_INSTALL/preflight/presentation.sh
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
sudo pacman -Syu --noconfirm

# Reboot
show_logo laseretch 920
show_subtext "You're done! So we'll be rebooting now..."
sleep 2
reboot
