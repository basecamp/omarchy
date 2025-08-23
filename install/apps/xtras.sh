#!/bin/bash

if [ -z "$OMARCHY_BARE" ]; then
  yay -S --noconfirm --needed \
    gnome-calculator gnome-keyring \
    localsend-bin ncspot cmus sptlrx

# Copy over Omarchy applications
source omarchy-refresh-applications || true
