#!/bin/bash

abort() {
  echo -e "\e[31mOmarchy install requires: $1\e[0m"
  echo
  # Use `read` here, because `gum` is not yet available.
  read -n 1 -p "Proceed anyway on your own accord and without assistance? [y/n]: " response
  case "$response" in
    [yY])
      echo
      ;;
    *)
      exit 1
      ;;
  esac
}

# Must be an Arch distro
[[ -f /etc/arch-release ]] || abort "Vanilla Arch"

# Must not be an Arch derivative distro
for marker in /etc/cachyos-release /etc/eos-release /etc/garuda-release /etc/manjaro-release; do
  [[ -f "$marker" ]] && abort "Vanilla Arch"
done

# Must not be runnig as root
[ "$EUID" -eq 0 ] && abort "Running as user (not root)"

# Must be x86 only to fully work
[ "$(uname -m)" != "x86_64" ] && abort "x86_64 CPU"

# Must not have Gnome or KDE already install
pacman -Qe gnome-shell &>/dev/null && abort "Fresh + Vanilla Arch"
pacman -Qe plasma-desktop &>/dev/null && abort "Fresh + Vanilla Arch"

# Cleared all guards
echo "Guards: OK"
