#!/bin/bash
set -euo pipefail

if ! command -v ufw &>/dev/null; then
  yay -Sy --noconfirm --needed ufw
  # Allow nothing in, everything out
  sudo ufw default deny incoming
  sudo ufw default allow outgoing

  # Allow ports for LocalSend
  sudo ufw allow 53317/udp
  sudo ufw allow 53317/tcp

  # Allow SSH in
  sudo ufw allow 22/tcp

  # Allow Docker containers to use DNS on host
  sudo ufw allow in on docker0 to any port 53

  # Turn on the firewall
  sudo ufw enable
fi

# Remove any existing ufw-docker installation
yay -Rns --noconfirm ufw-docker || true
command -v ufw-docker &>/dev/null && sudo ufw-docker uninstall || true
# Install ufw-docker
if ! command -v ufw-docker &>/dev/null; then
  sudo rm -f /usr/local/bin/ufw-docker

  # Download and install ufw-docker
  sudo wget -O /usr/local/bin/ufw-docker \
  https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker

  # Make it executable
  sudo chmod +x /usr/local/bin/ufw-docker

  # Install ufw-docker
  sudo ufw-docker install
  sudo ufw reload
fi