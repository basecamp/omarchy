#!/bin/bash

# Install bluetooth controls
sudo pacman -S --noconfirm --needed blueberry

# Turn on bluetooth by default
chrootable_systemctl_enable bluetooth.service
