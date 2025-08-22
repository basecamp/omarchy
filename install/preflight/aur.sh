#!/bin/bash

# Detect offline environment
is_offline_environment() {
    # Check if offline yay binary is available
    if [ -f "/usr/local/bin/yay-offline" ] || [ -f "/var/cache/omarchy/packages/yay" ]; then
        return 0
    fi
    
    # Check network connectivity as fallback
    if ! ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Install yay from offline binary
install_yay_offline() {
    echo "Installing yay from offline binary..."
    
    local yay_source=""
    if [ -f "/usr/local/bin/yay-offline" ]; then
        yay_source="/usr/local/bin/yay-offline"
    elif [ -f "/var/cache/omarchy/packages/yay" ]; then
        yay_source="/var/cache/omarchy/packages/yay"
    else
        echo "Offline yay binary not found"
        return 1
    fi
    
    # Install yay binary
    sudo cp "$yay_source" /usr/local/bin/yay
    sudo chmod +x /usr/local/bin/yay
    
    # Verify installation
    if ! /usr/local/bin/yay --version >/dev/null 2>&1; then
        echo "Offline yay binary verification failed"
        return 1
    fi
    
    echo "✓ Offline yay binary installed successfully"
    
    # Create state file for tracking
    mkdir -p ~/.local/share/omarchy/state
    touch ~/.local/share/omarchy/state/yay-offline-installed
    
    return 0
}

# Install build tools
sudo pacman -Sy --needed --noconfirm base-devel

# Only add Chaotic-AUR if the architecture is x86_64 so ARM users can build the packages
if [[ "$(uname -m)" == "x86_64" ]] && [ -z "$DISABLE_CHAOTIC" ] && ! command -v yay &>/dev/null; then
  # Check for network connectivity before attempting Chaotic-AUR installation
  if ping -c1 -W5 1.1.1.1 >/dev/null 2>&1; then
    # Try installing Chaotic-AUR keyring and mirrorlist
    if ! pacman-key --list-keys 3056513887B78AEB >/dev/null 2>&1 &&
      sudo pacman-key --recv-key 3056513887B78AEB &&
      sudo pacman-key --lsign-key 3056513887B78AEB &&
      sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' &&
      sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'; then

      # Add Chaotic-AUR repo to pacman config
      if ! grep -q "chaotic-aur" /etc/pacman.conf; then
        echo -e '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf >/dev/null
      fi

      # Install yay directly from Chaotic-AUR
      sudo pacman -Sy --needed --noconfirm yay
      
      # Create state file
      mkdir -p ~/.local/share/omarchy/state
      touch ~/.local/share/omarchy/state/chaotic-aur-installed
    else
      echo "Failed to install Chaotic-AUR, so won't include it in pacman config!"
      mkdir -p ~/.local/share/omarchy/state
      touch ~/.local/share/omarchy/state/chaotic-aur-failed
    fi
  else
    echo "No network connectivity - skipping Chaotic-AUR installation"
    mkdir -p ~/.local/share/omarchy/state
    touch ~/.local/share/omarchy/state/chaotic-aur-skipped-offline
  fi
fi

# Manually install yay from AUR if not already available
if ! command -v yay &>/dev/null; then
  # Try offline installation if in offline environment
  if is_offline_environment; then
    echo "Offline environment detected, attempting offline yay installation..."
    if install_yay_offline; then
      echo "✓ Offline yay installation completed successfully"
    else
      echo "⚠ Offline yay installation failed"
      # Don't fall back to online if we're clearly offline
      if ! ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        echo "✗ No network available and offline installation failed"
        exit 1
      fi
      echo "Network available, falling back to online installation..."
    fi
  fi
  
  # Online installation if offline failed or not available
  if ! command -v yay &>/dev/null; then
    if ping -c1 -W5 1.1.1.1 >/dev/null 2>&1; then
      cd /tmp
      rm -rf yay-bin
      git clone https://aur.archlinux.org/yay-bin.git
      cd yay-bin
      makepkg -si --noconfirm
      cd -
      rm -rf yay-bin
      cd ~
      
      # Create state file
      mkdir -p ~/.local/share/omarchy/state
      touch ~/.local/share/omarchy/state/yay-aur-installed
    else
      echo "No network connectivity - cannot install yay from AUR"
      exit 1
    fi
  fi
fi

# Add fun and color to the pacman installer
if ! grep -q "ILoveCandy" /etc/pacman.conf; then
  sudo sed -i '/^\[options\]/a Color\nILoveCandy' /etc/pacman.conf
fi