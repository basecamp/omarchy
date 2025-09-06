#!/usr/bin/env bash

echo "Enable and start the UFW service"
if systemctl is-enabled --quiet ufw.service && systemctl is-active --quiet ufw.service; then
  # UFW is already enabled and running, nothing to change
  :
else
  sudo systemctl enable --now ufw.service
fi
