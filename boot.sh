#!/bin/bash

# Set install mode to online since boot.sh is used for curl installations
export OMARCHY_ONLINE_INSTALL=true

OMARCHY_REPO="${OMARCHY_REPO:-basecamp/omarchy}" # custom repo with default fallback
OMARCHY_REF="${OMARCHY_REF:-master}" # custom branch/ref with default fallback

# Detect virtualization
if command -v systemd-detect-virt &>/dev/null; then
  virt_type=$(systemd-detect-virt || echo "none")

  # Set universal virtualization flag for any VM
  if [[ "$virt_type" != "none" ]]; then
    export OMARCHY_VIRTUALIZATION=true
  fi
fi

omarchy_art="Omarchy"
# Use simple ASCII on Asahi and VMs, Unicode elsewhere
if uname -r | grep -qi "asahi" || [[ -n "$OMARCHY_VIRTUALIZATION" ]]; then
  curl -fsSL "https://raw.githubusercontent.com/${OMARCHY_REPO}/${OMARCHY_REF}/logo-ascii.txt" -o /tmp/omarchy-logo-ascii.txt 2>/dev/null
  if [ -f /tmp/omarchy-logo-ascii.txt ]; then
    omarchy_art="$(cat /tmp/omarchy-logo-ascii.txt)"
  fi
else
  curl -fsSL "https://raw.githubusercontent.com/${OMARCHY_REPO}/${OMARCHY_REF}/logo.txt" -o /tmp/omarchy-logo.txt 2>/dev/null
  if [ -f /tmp/omarchy-logo.txt ]; then
    omarchy_art="$(cat /tmp/omarchy-logo.txt)"
  fi
fi

clear
echo -e "\n$omarchy_art\n"

# Use custom branch if instructed, otherwise default to master
OMARCHY_REF="${OMARCHY_REF:-master}"

# Set mirror based on branch
if [[ $OMARCHY_REF == "dev" ]]; then
  export OMARCHY_MIRROR=edge
  echo 'Server = https://mirror.omarchy.org/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
elif [[ $OMARCHY_REF == "rc" ]]; then
  export OMARCHY_MIRROR=rc
  echo 'Server = https://rc-mirror.omarchy.org/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
else
  export OMARCHY_MIRROR=stable
  echo 'Server = https://stable-mirror.omarchy.org/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
fi

sudo pacman -Syu --noconfirm --needed git

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

echo -e "\nCloning Omarchy from: https://github.com/${OMARCHY_REPO}.git"
rm -rf ~/.local/share/omarchy/
git clone "https://github.com/${OMARCHY_REPO}.git" ~/.local/share/omarchy >/dev/null

echo -e "\e[32mUsing branch: $OMARCHY_REF\e[0m"
cd ~/.local/share/omarchy
git fetch origin "${OMARCHY_REF}" && git checkout "${OMARCHY_REF}"
cd -

echo -e "\nInstallation starting..."
source ~/.local/share/omarchy/install.sh
