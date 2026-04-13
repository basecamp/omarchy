#!/usr/bin/env bash
# Install system-sleep hook to prevent GPU suspend hang (omarchy#5277)
[ "$(id -u)" -eq 0 ] && SUDO="" || SUDO="sudo"
$SUDO mkdir -p /etc/systemd/system-sleep
$SUDO install -m 0755 -o root -g root "$OMARCHY_PATH/default/systemd/system-sleep/nvidia-hyprlock" /etc/systemd/system-sleep/
