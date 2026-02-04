#!/bin/bash

if ! command -v tzupdate &>/dev/null; then
  yay -S --noconfirm --needed tzupdate
  sudo tee /etc/sudoers.d/autarky-tzupdate >/dev/null <<EOF
%wheel ALL=(root) NOPASSWD: /usr/bin/tzupdate, /usr/bin/timedatectl
EOF
  sudo chmod 0440 /etc/sudoers.d/autarky-tzupdate
fi
