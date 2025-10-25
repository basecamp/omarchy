#!/bin/bash

# add ssh keys to ssh-agent
mkdir -p ~/.ssh
echo 'AddKeysToAgent yes' | tee -a ~/.ssh/config >/dev/null

# Ensure Hyprland picks up the SSH_AUTH_SOCK variable
echo 'env = SSH_AUTH_SOCK,$XDG_RUNTIME_DIR/ssh-agent.socket' | tee -a ~/.config/hypr/envs.conf >/dev/null

# Start ssh-agent automatically for user
systemctl enable --now --user ssh-agent.service

echo 'SSH Agent has been installed and enabled'
touch ~/.local/state/omarchy/relaunch-required
omarchy-update-restart