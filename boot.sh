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

clear
echo -e "\n$ansi_art\n"

sudo pacman -Syu --noconfirm --needed git

# Use custom repo if specified, otherwise default to basecamp/omarchy
OMARCHY_REPO="${OMARCHY_REPO:-basecamp/omarchy}"

# Support for China-friendly Git mirrors
# Users can set OMARCHY_GIT_MIRROR to use alternative Git hosting services
# Examples: github.com (default), gitee.com, gitcode.com
OMARCHY_GIT_MIRROR="${OMARCHY_GIT_MIRROR:-github.com}"

echo -e "\nCloning Omarchy from: https://${OMARCHY_GIT_MIRROR}/${OMARCHY_REPO}.git"
rm -rf ~/.local/share/omarchy/
if ! git clone "https://${OMARCHY_GIT_MIRROR}/${OMARCHY_REPO}.git" ~/.local/share/omarchy >/dev/null 2>&1; then
  # Fallback to GitHub if the mirror fails
  if [[ "${OMARCHY_GIT_MIRROR}" != "github.com" ]]; then
    echo -e "\nFailed to clone from ${OMARCHY_GIT_MIRROR}, falling back to github.com..."
    if ! git clone "https://github.com/${OMARCHY_REPO}.git" ~/.local/share/omarchy >/dev/null 2>&1; then
      echo -e "\nError: Failed to clone repository from github.com"
      exit 1
    fi
  else
    # If already trying github.com and it fails, exit with error
    echo -e "\nError: Failed to clone repository from github.com"
    exit 1
  fi
fi

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
