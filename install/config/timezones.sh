#!/bin/bash

if [[ ! -f /etc/sudoers.d/omarchy-tzupdate ]]; then
  yay -S --noconfirm --needed tzupdate
  sudo tee /etc/sudoers.d/omarchy-tzupdate >/dev/null <<EOF
%wheel ALL=(root) NOPASSWD: /usr/bin/tzupdate, /usr/bin/timedatectl
EOF
  sudo chmod 0440 /etc/sudoers.d/omarchy-tzupdate
fi
