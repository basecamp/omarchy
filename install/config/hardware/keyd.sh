#!/bin/bash

# Install keyd and configure keyboard remapping for Mac-style keyboards

# Install keyd if not already installed
if ! yay -Qq keyd &>/dev/null; then
  echo "Installing keyd (keyboard remapping daemon)"
  yay -S --noconfirm --needed keyd || true
fi

# Create keyd config directory
sudo mkdir -p /etc/keyd

# Create keyd config file
if [[ ! -f /etc/keyd/default.conf ]]; then
  echo "Creating keyd config for keyboard remapping"
  cat <<EOF | sudo tee /etc/keyd/default.conf >/dev/null
[ids]
*
[main]
leftmeta+leftshift+3 = sysrq
leftmeta+leftshift+4 = sysrq
EOF
fi

# Enable and start keyd service
if ! systemctl is-enabled --quiet keyd.service; then
  echo "Enabling keyd service"
  sudo systemctl enable --now keyd.service || true
fi
