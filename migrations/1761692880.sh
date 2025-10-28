#!/bin/bash

echo "Ensure pacman multilib repository is enabled for 32-bit packages"

if ! grep -Eq '^\[multilib\]' /etc/pacman.conf; then
  if grep -Eq '^[[:space:]]*#[[:space:]]*\[multilib\]' /etc/pacman.conf; then
    sudo sed -i 's/^[[:space:]]*#[[:space:]]*\[multilib\]/[multilib]/' /etc/pacman.conf
    sudo sed -i '/^\[multilib\]/{n;s/^[[:space:]]*#[[:space:]]*Include/Include/}' /etc/pacman.conf
  else
    sudo bash -c 'printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" >> /etc/pacman.conf'
  fi
  sudo pacman -Sy
fi
