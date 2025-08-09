#!/bin/bash

abort() {
  echo -e "\e[31mOmarchy is only designed for a fresh Arch install!\e[0m"
  exit 1
}

# Must be an Arch distro
[[ -f /etc/arch-release ]] || abort

# Must not be an Arch derivative distro
for marker in /etc/cachyos-release /etc/eos-release /etc/garuda-release /etc/manjaro-release; do
  [[ -f "$marker" ]] && abort
done

# Must not have Gnome or KDE already install
pacman -Qe gnome-shell &>/dev/null && abort
pacman -Qe plasma-desktop &>/dev/null && abort
