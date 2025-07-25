#!/bin/bash

show_logo
show_subtext "Installing printer system..."

sudo pacman -S --noconfirm cups cups-pdf cups-filters system-config-printer
sudo systemctl enable --now cups.service
