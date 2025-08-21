#!/bin/bash

# Install bluetooth controls
yay -S --noconfirm --needed bluetui

# Turn on bluetooth by default
chrootable_systemctl_enable bluetooth.service
