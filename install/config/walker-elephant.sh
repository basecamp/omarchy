#!/bin/bash

# Install elephant systemd service
install -D -m 644 $OMARCHY_PATH/default/systemd/user/elephant.service ~/.config/systemd/user/elephant.service

# Enable the service
systemctl enable --user elephant.service
