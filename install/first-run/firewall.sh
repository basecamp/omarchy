#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Detect local network CIDR via routing table
IFACE=$(ip route show default | awk '{print $5; exit}')
if [[ -z "${IFACE:-}" ]]; then
  echo "ERROR: Cannot detect default network interface." >&2
  exit 1
fi

NETWORK=$(ip route show | awk -v iface="$IFACE" '$0 ~ iface && /proto kernel/ {print $1; exit}')
if [[ -z "${NETWORK:-}" ]]; then
  echo "ERROR: Cannot detect local network CIDR for interface ${IFACE}." >&2
  exit 1
fi

# Allow nothing in, everything out
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow ports for LocalSend — only from local network
sudo ufw allow from "${NETWORK}" to any port 53317 proto udp comment 'LocalSend UDP (LAN only)'
sudo ufw allow from "${NETWORK}" to any port 53317 proto tcp comment 'LocalSend TCP (LAN only)'

# Allow Docker containers to use DNS on host
sudo ufw allow in proto udp from 172.16.0.0/12 to 172.17.0.1 port 53 comment 'allow-docker-dns'

# Turn on the firewall
sudo ufw --force enable

# Enable UFW systemd service to start on boot
sudo systemctl enable ufw

# Turn on Docker protections
sudo ufw-docker install
sudo ufw reload
