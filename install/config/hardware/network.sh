#!/bin/bash

# Ensure iwd service will be started
sudo systemctl enable iwd.service

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

# Provide domain name resolution for software that reads /etc/resolv.conf directly
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf