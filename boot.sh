#!/bin/bash

# Set install mode to online since boot.sh is used for curl installations
export OMARCHY_ONLINE_INSTALL=true

ansi_art='                 ▄▄▄                                                   
 ▄█████▄    ▄███████████▄    ▄███████   ▄███████   ▄███████   ▄█   █▄    ▄█   █▄ 
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   █▀   ███   ███  ███   ███
███   ███  ███   ███   ███ ▄███▄▄▄███ ▄███▄▄▄██▀  ███       ▄███▄▄▄███▄ ███▄▄▄███
███   ███  ███   ███   ███ ▀███▀▀▀███ ▀███▀▀▀▀    ███      ▀▀███▀▀▀███  ▀▀▀▀▀▀███
███   ███  ███   ███   ███  ███   ███ ██████████  ███   █▄   ███   ███  ▄██   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
 ▀█████▀    ▀█   ███   █▀   ███   █▀   ███   ███  ███████▀   ███   █▀    ▀█████▀ 
                                       ███   █▀                                  '
# Detect virtualization
if command -v systemd-detect-virt &>/dev/null; then
  virt_type=$(systemd-detect-virt || echo "none")

  # Set universal virtualization flag for any VM
  if [[ "$virt_type" != "none" ]]; then
    export OMARCHY_VIRTUALIZATION=true
  fi
fi


clear
echo -e "\n$ansi_art\n"

# Install git early since it's needed when running boot.sh as a non-root user
if ! command -v git &>/dev/null; then
  echo "Installing git..."
  sudo pacman -S --noconfirm --needed git >/dev/null 2>&1 || {
    echo "Error: Failed to install git"
    exit 1
  }
  echo "Git installed successfully"
  echo
fi

# Install the 'less' package early in case we error out and need to show logs
if ! command -v less &>/dev/null; then
  echo "Installing less..."
  sudo pacman -S --noconfirm --needed less >/dev/null 2>&1 || {
    echo "Error: Failed to install less"
    exit 1
  }
  echo "Less installed successfully"
  echo
fi

if [[ $EUID -eq 0 ]]; then
  echo "------------------------------------------------------"
  echo "Running as Root - Setting up non-root user for Omarchy"
  echo "------------------------------------------------------"

  curl -s "https://raw.githubusercontent.com/${OMARCHY_REPO}/${OMARCHY_REF}/install/bootstrap/user-setup.sh" | \
    OMARCHY_REPO="${OMARCHY_REPO}" OMARCHY_REF="${OMARCHY_REF}" bash

  # user-setup.sh will create user and re-run boot.sh as that user, then exit
  exit 0 # exit to not run the rest of the script, and avoid cloning as root
fi

# Use custom repo if specified, otherwise default to basecamp/omarchy
OMARCHY_REPO="${OMARCHY_REPO:-basecamp/omarchy}"

echo -e "\nCloning Omarchy from: https://github.com/${OMARCHY_REPO}.git"
rm -rf ~/.local/share/omarchy/
git clone "https://github.com/${OMARCHY_REPO}.git" ~/.local/share/omarchy >/dev/null

# Use custom branch if instructed, otherwise default to master
OMARCHY_REF="${OMARCHY_REF:-master}"
if [[ $OMARCHY_REF != "master" ]]; then
  echo -e "\e[32mUsing branch: $OMARCHY_REF\e[0m"
  cd ~/.local/share/omarchy
  git fetch origin "${OMARCHY_REF}" && git checkout "${OMARCHY_REF}"
  cd -
fi

echo -e "\nInstallation starting..."
source ~/.local/share/omarchy/install.sh
