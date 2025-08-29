#!/bin/bash

# Migration to fix DNS issue for existing users who already ran 1755109182.sh
# Remove UseDNS=no from all network files to allow DHCP DNS
# This matches what omarchy-setup-dns DHCP does

echo "Removing UseDNS=no from network files to fix DNS issue..."

for file in /etc/systemd/network/*.network; do
  [[ -f "$file" ]] || continue
  if grep -q "^UseDNS=no" "$file"; then
    echo "Removing UseDNS=no from $file"
    sudo sed -i '/^UseDNS=no/d' "$file"
  fi
done

echo "DNS migration completed - DHCP DNS should work after reboot"