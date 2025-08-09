#!/bin/bash

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
  
  # Check for wget or curl
  if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    missing_deps+=("wget or curl")
  fi
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    echo -e "\e[33mWarning: Missing required prerequisites!\e[0m"
    echo "The following commands are required but not found:"
    for dep in "${missing_deps[@]}"; do
      echo "  - $dep"
    done
    echo
    echo "Would you like to install the missing prerequisites now?"
    
    # Determine the correct install command
    local install_cmd
    if [[ " ${missing_deps[*]} " =~ " wget or curl " ]]; then
      # Replace "wget or curl" with "wget" for the actual installation
      local filtered_deps=()
      for dep in "${missing_deps[@]}"; do
        if [[ "$dep" == "wget or curl" ]]; then
          filtered_deps+=("wget")
        else
          filtered_deps+=("$dep")
        fi
      done
      install_cmd="pacman -S ${filtered_deps[*]}"
      echo "Command to run: $install_cmd  # (choosing wget over curl)"
    else
      install_cmd="pacman -S ${missing_deps[*]}"
      echo "Command to run: $install_cmd"
    fi
    
    echo -n "Install missing dependencies? [Y/n]: "
    read -r response
    
    # Default to yes if empty response
    if [[ -z "$response" || "$response" =~ ^[Yy]$ ]]; then
      echo "Installing missing dependencies..."
      if sudo $install_cmd --noconfirm; then
        echo -e "\e[32mDependencies installed successfully!\e[0m"
        echo "Continuing with installation..."
      else
        echo -e "\e[31mFailed to install dependencies!\e[0m"
        echo "Please install them manually and try again."
        exit 1
      fi
    else
      echo "Installation cancelled. Please install the missing prerequisites manually:"
      echo "  $install_cmd"
      exit 1
    fi
  fi
}

clear
echo -e "\n$ansi_art\n"

# Run prerequisite check
check_prerequisites

sudo pacman -Sy --noconfirm --needed git

# Use custom repo if specified, otherwise default to basecamp/omarchy
OMARCHY_REPO="${OMARCHY_REPO:-basecamp/omarchy}"

echo -e "\nCloning Omarchy from: https://github.com/${OMARCHY_REPO}.git"
rm -rf ~/.local/share/omarchy/
git clone "https://github.com/${OMARCHY_REPO}.git" ~/.local/share/omarchy >/dev/null

# Use custom branch if instructed
if [[ -n "$OMARCHY_REF" ]]; then
  echo -e "\eUsing branch: $OMARCHY_REF"
  cd ~/.local/share/omarchy
  git fetch origin "${OMARCHY_REF}" && git checkout "${OMARCHY_REF}"
  cd -
fi

echo -e "\nInstallation starting..."
source ~/.local/share/omarchy/install.sh
