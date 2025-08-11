#!/bin/bash

abort() {
  echo -e "\e[31mOmarchy requires a fresh vanilla Arch install and running on x86_64 as user.\e[0m"

  if gum confirm "Proceed anyway on your own accord and without assistance?"; then
    exit 0
  else
    exit 1
  fi
}

# Must be an Arch distro
[[ -f /etc/arch-release ]] || abort

# Must not be an Arch derivative distro
for marker in /etc/cachyos-release /etc/eos-release /etc/garuda-release /etc/manjaro-release; do
  [[ -f "$marker" ]] && abort
done

# Must not be runnig as root
[ "$EUID" -eq 0 ] && abort

# Must be x86 only to fully work
[ "$(uname -m)" != "x86_64" ] && abort

# Must not have Gnome or KDE already install
pacman -Qe gnome-shell &>/dev/null && abort
pacman -Qe plasma-desktop &>/dev/null && abort

# All guards have been cleared!
echo -e "\e[32mOmarchy sees a fresh vanilla Arch install running on x86_64 as user.\e[0m"
