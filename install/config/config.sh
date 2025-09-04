#!/bin/bash

# Copy over Omarchy configs
mkdir -p ~/.config
cp -R ~/.local/share/omarchy/config/* ~/.config/

# Use default zshrc from Omarchy
cp ~/.local/share/omarchy/default/zshrc ~/.zshrc
