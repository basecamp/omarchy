#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() {
  echo -e "${GREEN}$1${NC}"
}

print_error() {
  echo -e "${RED}$1${NC}"
}

print_info() {
  echo -e "${YELLOW}$1${NC}"
}

check_fido2_hardware() {
  tokens=$(fido2-token -L 2>/dev/null)
  if [ -z "$tokens" ]; then
    print_error "\nNo FIDO2 device detected. Please plug it in (you may need to unlock it as well)."
    return 1
  fi
  return 0
}

setup_pam_config() {
  # Configure sudo
  if ! grep -q pam_u2f.so /etc/pam.d/sudo; then
    print_info "Configuring sudo for FIDO2 authentication..."
    sudo sed -i '1i auth    sufficient pam_u2f.so cue authfile=/etc/fido2/fido2' /etc/pam.d/sudo
  fi

  # Configure polkit
  if [ -f /etc/pam.d/polkit-1 ] && ! grep -q 'pam_u2f.so' /etc/pam.d/polkit-1; then
    print_info "Configuring polkit for FIDO2 authentication..."
    sudo sed -i '1i auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2' /etc/pam.d/polkit-1
  elif [ ! -f /etc/pam.d/polkit-1 ]; then
    print_info "Creating polkit configuration with FIDO2 authentication..."
    sudo tee /etc/pam.d/polkit-1 >/dev/null <<'EOF'
auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
EOF
  fi
}

remove_pam_config() {
  # Remove from sudo
  if grep -q pam_u2f.so /etc/pam.d/sudo; then
    print_info "Removing FIDO2 authentication from sudo..."
    sudo sed -i '/pam_u2f\.so/d' /etc/pam.d/sudo
  fi

  # Remove from polkit
  if [ -f /etc/pam.d/polkit-1 ] && grep -Fq 'pam_u2f.so' /etc/pam.d/polkit-1; then
    print_info "Removing FIDO2 authentication from polkit..."
    sudo sed -i '/pam_u2f\.so/d' /etc/pam.d/polkit-1
  fi
}

if [[ "--remove" == "$1" ]]; then
  print_success "Removing FIDO2 device from authentication.\n"

  # Remove PAM configuration
  remove_pam_config

  # Remove FIDO2 configuration
  if [ -d /etc/fido2 ]; then
    print_info "Removing FIDO2 configuration..."
    sudo rm -rf /etc/fido2
  fi

  # Uninstall packages
  print_info "Removing FIDO2 packages..."
  sudo pacman -Rns --noconfirm libfido2 pam-u2f

  print_success "FIDO2 authentication has been completely removed."
else
  print_success "Setting up FIDO2 device for authentication.\n"

  # Install required packages
  print_info "Installing required packages..."
  sudo pacman -S --noconfirm --needed libfido2 pam-u2f

  if ! check_fido2_hardware; then
    exit 1
  fi

  # Create the pamu2fcfg file
  if [ ! -f /etc/fido2/fido2 ]; then
    sudo mkdir -p /etc/fido2
    print_success "\nLet's setup your device by confirming on the device now."
    print_info "Touch your FIDO2 key when it lights up...\n"

    if pamu2fcfg >/tmp/fido2; then
      sudo mv /tmp/fido2 /etc/fido2/fido2
      print_success "FIDO2 device registered successfully!"
    else
      print_error "\nFIDO2 registration failed. Please try again."
      exit 1
    fi
  else
    print_info "FIDO2 device already registered."
  fi

  # Configure PAM
  setup_pam_config

  # Test with sudo
  print_info "\nTesting FIDO2 authentication with sudo..."
  print_info "Touch your FIDO2 key when prompted.\n"

  if sudo echo "FIDO2 authentication test successful"; then
    print_success "\nPerfect! FIDO2 authentication is now configured."
    print_info "You can use your FIDO2 key for sudo and polkit authentication."
  else
    print_error "\nVerification failed. You may want to check your configuration."
  fi
fi
