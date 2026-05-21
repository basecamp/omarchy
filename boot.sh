#!/bin/bash
# Curl-able Omarchy bootstrap. Configures the omarchy pacman repo on a fresh
# Arch system, installs the omarchy-installer package (which pulls omarchy,
# omarchy-settings, and omarchy-limine via depends), then hands off to
# `omarchy install`.
#
# Usage:
#   curl -sSL https://omarchy.org/boot.sh | bash
#   curl -sSL https://omarchy.org/boot.sh | OMARCHY_REF=dev bash

set -e

ansi_art='                 ▄▄▄
 ▄█████▄    ▄███████████▄    ▄███████   ▄███████   ▄███████   ▄█   █▄    ▄█   █▄
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   █▀   ███   ███  ███   ███
███   ███  ███   ███   ███ ▄███▄▄▄███ ▄███▄▄▄██▀  ███       ▄███▄▄▄███▄ ███▄▄▄███
███   ███  ███   ███   ███ ▀███▀▀▀███ ▀███▀▀▀▀    ███      ▀▀███▀▀▀███  ▀▀▀▀▀▀███
███   ███  ███   ███   ███  ███   ███ ██████████  ███   █▄   ███   ███  ▄██   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
 ▀█████▀    ▀█   ███   █▀   ███   █▀   ███   ███  ███████▀   ███   █▀    ▀█████▀
                                       ███   █▀                                  '
clear
echo -e "\n$ansi_art\n"

# Pick the omarchy package channel. stable is the default; dev/rc are for
# pre-release testing.
case "${OMARCHY_REF:-master}" in
  dev) channel=edge ;;
  rc)  channel=rc ;;
  *)   channel=stable ;;
esac

echo "Configuring omarchy [${channel}] pacman repo..."
sudo tee /etc/pacman.d/omarchy.conf >/dev/null <<EOF
[omarchy]
SigLevel = Optional TrustAll
Server = https://pkgs.omarchy.org/${channel}/\$arch
EOF
if ! grep -q '^Include = /etc/pacman.d/omarchy.conf' /etc/pacman.conf; then
  echo -e "\nInclude = /etc/pacman.d/omarchy.conf" | sudo tee -a /etc/pacman.conf >/dev/null
fi

echo "Refreshing pacman databases..."
sudo pacman -Sy --noconfirm

echo "Installing omarchy-installer..."
sudo pacman -S --noconfirm --needed omarchy-installer

echo -e "\nInstallation starting..."
exec omarchy-install
