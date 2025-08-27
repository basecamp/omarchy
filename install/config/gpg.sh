#!/bin/bash

# Setup GPG configuration with multiple keyservers for better reliability
sudo mkdir -p /etc/gnupg
OMARCHY_REPO_DIR="$(dirname "$OMARCHY_INSTALL")/.."
sudo cp "$OMARCHY_REPO_DIR/default/gpg/dirmngr.conf" /etc/gnupg/ 2>/dev/null || sudo cp ~/.local/share/omarchy/default/gpg/dirmngr.conf /etc/gnupg/ 2>/dev/null || true
sudo chmod 644 /etc/gnupg/dirmngr.conf 2>/dev/null || true
sudo gpgconf --kill dirmngr || true
sudo gpgconf --launch dirmngr || true
