#!/bin/bash

# Set install mode to online since boot.sh is used for curl installations
export OMARCHY_ONLINE_INSTALL=true

# Detect virtualization
if command -v systemd-detect-virt &>/dev/null; then
  virt_type=$(systemd-detect-virt || echo "none")

  # Set universal virtualization flag for any VM
  if [[ "$virt_type" != "none" ]]; then
    export OMARCHY_VIRTUALIZATION=true
  fi
fi

# Use simple ASCII on Asahi and VMs, Unicode elsewhere
if uname -r | grep -qi "asahi" || [[ -n "$OMARCHY_VIRTUALIZATION" ]]; then
  omarchy_art='                 ***
 *#####*    *###########*    *#######   *#######   *#######   *#   #*    *#   #*
*##   ##*  *##   ###   ##*  *##   ###  *##   ###  *##   ***  *##   ##*  *##   ##*
###   ###  ###   ###   ###  ###   ###  ###   ###  ###   **   ###   ###  ###   ###
###   ###  ###   ###   ###  ###   ###  ###   ###  ###       *###   ###* ###   ###
###   ###  ###   ###   ### ########## ########    ###      *##########  #########
###   ###  ###   ###   ###  ###   ###  ####       ###        ###   ###        ###
###   ###  ###   ###   ###  ###   ### ##########  ###   ##   ###   ###   ##   ###
###   ###  ###   ###   ###  ###   ###  ###   ###  ###   ###  ###   ###  ###   ###
 #######    ##   ###   ##   ###   ##   ###   ###  ########   ###   ##    ######
                                       ###   ##                                  '
else
  omarchy_art='                 ▄▄▄
 ▄█████▄    ▄███████████▄    ▄███████   ▄███████   ▄███████   ▄█   █▄    ▄█   █▄
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   █▀   ███   ███  ███   ███
███   ███  ███   ███   ███ ▄███▄▄▄███ ▄███▄▄▄██▀  ███       ▄███▄▄▄███▄ ███▄▄▄███
███   ███  ███   ███   ███ ▀███▀▀▀███ ▀███▀▀▀▀    ███      ▀▀███▀▀▀███  ▀▀▀▀▀▀███
███   ███  ███   ███   ███  ███   ███ ██████████  ███   █▄   ███   ███  ▄██   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
 ▀█████▀    ▀█   ███   █▀   ███   █▀   ███   ███  ███████▀   ███   █▀    ▀█████▀ 
                                       ███   █▀                                  '
fi

clear
echo -e "\n$omarchy_art\n"

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

OMARCHY_REPO="${OMARCHY_REPO:-basecamp/omarchy}" # custom repo with default fallback
OMARCHY_REF="${OMARCHY_REF:-master}" # custom branch/ref with default fallback

if [[ $EUID -eq 0 ]]; then
  echo "------------------------------------------------------"
  echo "Running as Root - Setting up non-root user for Omarchy"
  echo "------------------------------------------------------"

  curl -s "https://raw.githubusercontent.com/${OMARCHY_REPO}/${OMARCHY_REF}/install/bootstrap/user-setup.sh" | \
    OMARCHY_REPO="${OMARCHY_REPO}" OMARCHY_REF="${OMARCHY_REF}" bash

  # user-setup.sh will create user and re-run boot.sh as that user, then exit
  exit 0 # exit to not run the rest of the script, and avoid cloning as root
fi

echo -e "\nCloning Omarchy from: https://github.com/${OMARCHY_REPO}.git"
rm -rf ~/.local/share/omarchy/

if [[ $OMARCHY_REF != "master" ]]; then
  echo -e "\e[32mUsing branch: $OMARCHY_REF (shallow clone)\e[0m"
  git clone --depth 1 --branch "${OMARCHY_REF}" "https://github.com/${OMARCHY_REPO}.git" ~/.local/share/omarchy >/dev/null
else
  git clone "https://github.com/${OMARCHY_REPO}.git" ~/.local/share/omarchy >/dev/null
fi

echo -e "\nInstallation starting..."
source ~/.local/share/omarchy/install.sh </dev/null
