#!/bin/bash

echo "Setting up 1Password extension policies for Chromium and Brave"

# Create directories for Chromium policies
sudo mkdir -p /etc/chromium/policies/managed
sudo chmod 755 /etc/chromium/policies /etc/chromium/policies/managed

# Create directories for Brave policies
sudo mkdir -p /etc/brave/policies/managed
sudo chmod 755 /etc/brave/policies /etc/brave/policies/managed

# Copy 1Password extension policy from omarchy config to system directories
sudo cp ~/.local/share/omarchy/config/chromium/policies/managed/onepassword.json /etc/chromium/policies/managed/onepassword.json
sudo chmod 644 /etc/chromium/policies/managed/onepassword.json

sudo cp ~/.local/share/omarchy/config/brave/policies/managed/onepassword.json /etc/brave/policies/managed/onepassword.json
sudo chmod 644 /etc/brave/policies/managed/onepassword.json

echo "1Password extension policies installed for Chromium and Brave"