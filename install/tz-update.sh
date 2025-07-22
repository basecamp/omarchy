#!/bin/bash

# Install tzupdate for Geo-IP lookups e.g. America/Chicago
yay -S --noconfirm --needed tzupdate

# Enable the tzupdate timer to check on boot and hourly
systemctl --user enable --now tzupdate.timer
