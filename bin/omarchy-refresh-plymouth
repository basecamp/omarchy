#!/bin/bash

sudo cp ~/.local/share/omarchy/default/plymouth/* /usr/share/plymouth/themes/omarchy/
sudo plymouth-set-default-theme omarchy

if command -v limine-mkinitcpio &>/dev/null; then
  sudo limine-mkinitcpio
else
  sudo mkinitcpio -P
fi
