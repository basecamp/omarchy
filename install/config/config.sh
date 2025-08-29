#!/bin/bash

# Backup existing configurations before overwriting them
echo -e "\nBacking up your existing configurations..."
source ~/.local/share/omarchy/install/config/backup-configs.sh

echo "Your original configurations have been backed up to:"
echo "   ~/.config/omarchy-backups/"
echo
echo "To manage your backups, use: omarchy-backup-manager"
echo

# Copy over Omarchy configs
mkdir -p ~/.config
cp -R ~/.local/share/omarchy/config/* ~/.config/

# Use default bashrc from Omarchy
cp ~/.local/share/omarchy/default/bashrc ~/.bashrc
