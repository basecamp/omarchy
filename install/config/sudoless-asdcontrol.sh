#!/bin/bash

# Setup sudo-less controls for controlling brightness on Apple Displays
echo "$USER ALL=(ALL) NOPASSWD: /usr/local/bin/asdcontrol" | sudo tee /etc/sudoers.d/asdcontrol
sudo chmod 440 /etc/sudoers.d/asdcontrol
