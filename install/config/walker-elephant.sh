#!/bin/bash

# Install elephant systemd service
install -D -m 644 $OMARCHY_PATH/default/systemd/user/elephant.service ~/.config/systemd/user/elephant.service

# Enable the service
systemctl enable --user elephant.service

# Create pacman hook to restart walker after updates
sudo mkdir -p /etc/pacman.d/hooks
sudo tee /etc/pacman.d/hooks/walker-restart.hook > /dev/null << EOF
[Trigger]
Type = Package
Operation = Upgrade
Target = walker
Target = walker-debug
Target = elephant*

[Action]
Description = Restarting Walker services after system update
When = PostTransaction
Exec = $OMARCHY_PATH/bin/omarchy-restart-walker
EOF
