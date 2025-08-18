#!/bin/bash

if ! command -v ufw &>/dev/null; then
  yay -S --noconfirm --needed ufw ufw-docker

  if is_chroot; then
    echo "⚠️  [CHROOT] Skipping firewall configuration in chroot environment"
    echo "    You will need to configure the firewall after booting into the installed system."
  else
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
    sudo ufw --force enable

    # Turn on Docker protections
    sudo ufw-docker install
    sudo ufw reload
  fi
fi
