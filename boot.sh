#!/bin/bash

# Set install mode to online since boot.sh is used for curl installations
export OMARCHY_ONLINE_INSTALL=true

OMARCHY_REPO="${OMARCHY_REPO:-basecamp/omarchy}" # custom repo with default fallback
OMARCHY_REF="${OMARCHY_REF:-master}" # custom branch/ref with default fallback

# Detect ARM architecture
arch=$(uname -m)
if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
  export OMARCHY_ARM=true

  # Detect Asahi Linux specifically
  if uname -r | grep -qi "asahi"; then
    export ASAHI_ALARM=true
  fi
fi

# Detect virtualization
if command -v systemd-detect-virt &>/dev/null; then
  virt_type=$(systemd-detect-virt || echo "none")

  # Set universal virtualization flag for any VM
  if [[ "$virt_type" != "none" ]]; then
    export OMARCHY_VIRTUALIZATION=true
  fi
fi

# Suppress gum help text on ARM/Asahi/VMs (Unicode doesn't render properly in raw TTY)
if [[ -n "$OMARCHY_ARM" ]] || [[ -n "$ASAHI_ALARM" ]] || [[ -n "$OMARCHY_VIRTUALIZATION" ]]; then
  export GUM_CONFIRM_SHOW_HELP=false
  export GUM_CHOOSE_SHOW_HELP=false
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

if [[ $EUID -eq 0 ]]; then
  echo "------------------------------------------------------"
  echo "Running as Root - Setting up non-root user for Omarchy"
  echo "------------------------------------------------------"

  curl -s "https://raw.githubusercontent.com/${OMARCHY_REPO}/${OMARCHY_REF}/install/bootstrap/user-setup.sh" | \
    OMARCHY_REPO="${OMARCHY_REPO}" OMARCHY_REF="${OMARCHY_REF}" OMARCHY_ARM="${OMARCHY_ARM:-}" bash

  # user-setup.sh will create user and re-run boot.sh as that user, then exit
  exit 0 # exit to not run the rest of the script, and avoid cloning as root
fi

# Update mirrorlist to avoid broken geo mirror before syncing database
if [[ -n "$OMARCHY_ARM" ]]; then
  echo "Configuring ARM mirrors (downloading from GitHub)..."
  if curl -fsSL "https://raw.githubusercontent.com/${OMARCHY_REPO}/${OMARCHY_REF}/default/pacman/mirrorlist.arm" -o /tmp/omarchy-mirrorlist.arm 2>/dev/null; then
    sudo cp -f /tmp/omarchy-mirrorlist.arm /etc/pacman.d/mirrorlist
    rm -f /tmp/omarchy-mirrorlist.arm
    echo "Updated mirrorlist to use Florida mirror (avoiding broken geo mirror)"
  else
    echo "Warning: Could not download mirrorlist, using system default"
  fi
fi

# Sync package database first to ensure we have current package versions
# This prevents 404 errors when trying to install git and less
echo
echo "Syncing package database..."
sync_attempts=0
max_sync_attempts=3
sync_success=false

while [ $sync_attempts -lt $max_sync_attempts ]; do
  if sudo pacman -Sy --noconfirm 2>&1; then
    sync_success=true
    break
  fi
  sync_attempts=$((sync_attempts + 1))
  if [ $sync_attempts -lt $max_sync_attempts ]; then
    echo "Database sync failed (attempt $sync_attempts/$max_sync_attempts), retrying in 3 seconds..."
    sleep 3
  fi
done

if [ "$sync_success" = false ]; then
  echo
  echo "ERROR: Failed to sync package database after $max_sync_attempts attempts"
  echo "This may be due to slow/unreachable mirrors or network issues."
  echo "Please check your network connection and try again."
  exit 1
fi

# Install git early since it's needed when running boot.sh as a non-root user
if ! command -v git &>/dev/null; then
  echo
  echo "Installing git..."
  git_output=$(mktemp)
  if ! sudo pacman -S --noconfirm --needed git >"$git_output" 2>&1; then
    echo "Error: Failed to install git"
    echo "--- pacman output ---"
    cat "$git_output"
    echo "---------------------"
    rm -f "$git_output"
    exit 1
  fi
  rm -f "$git_output"
  echo "Git installed successfully"
fi

# Install the 'less' package early in case we error out and need to show logs
if ! command -v less &>/dev/null; then
  echo
  echo "Installing less..."
  less_output=$(mktemp)
  if ! sudo pacman -S --noconfirm --needed less >"$less_output" 2>&1; then
    echo "Error: Failed to install less"
    echo "--- pacman output ---"
    cat "$less_output"
    echo "---------------------"
    rm -f "$less_output"
    exit 1
  fi
  rm -f "$less_output"
  echo "Less installed successfully"
fi

if [[ -n $OMARCHY_RESUME_INSTALL ]]; then
  echo -e "\n\e[32mResuming Omarchy installation from where it left off...\e[0m\n"
else
  echo -e "\nCloning Omarchy from: https://github.com/${OMARCHY_REPO}.git"

  rm -rf ~/.local/share/omarchy/

  if [[ $OMARCHY_REF != "master" ]]; then
    echo -e "\n\e[32mUsing branch: $OMARCHY_REF (shallow clone)\e[0m"
    git clone --quiet --depth 1 --branch "${OMARCHY_REF}" "https://github.com/${OMARCHY_REPO}.git" ~/.local/share/omarchy
  else
    git clone --quiet "https://github.com/${OMARCHY_REPO}.git" ~/.local/share/omarchy
  fi
fi

echo -e "\nInstallation starting..."
source ~/.local/share/omarchy/install.sh
