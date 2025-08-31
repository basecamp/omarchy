#!/bin/bash

clear
tte -i ~/.local/share/omarchy/logo.txt --frame-rate 920 laseretch
echo
echo "You're done! So we're ready to reboot now..." | tte --frame-rate 640 wipe

if sudo test -f /etc/sudoers.d/99-omarchy-installer; then
  sudo rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null
  echo -e "\nRemember to remove USB installer!\n\n"
fi

sleep 5
reboot
