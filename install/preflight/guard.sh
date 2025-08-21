#!/bin/bash

abort() {
  echo -e "\e[31mOmarchy install requires: $1\e[0m"
  echo
  gum confirm "Proceed anyway on your own accord and without assistance?" || exit 1
}

# Must not be runnig as root
[ "$EUID" -eq 0 ] && abort "Running as user (not root)"

# Must be x86 only to fully work
[ "$(uname -m)" != "x86_64" ] && abort "x86_64 CPU"

# Must not have Gnome or KDE already install
pacman -Qe gnome-shell &>/dev/null && abort "Fresh + Vanilla Arch/Arch-based"
pacman -Qe plasma-desktop &>/dev/null && abort "Fresh + Vanilla Arch/Arch-based"

# Cleared all guards
echo "Guards: OK"
