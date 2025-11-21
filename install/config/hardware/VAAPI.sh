#!/bin/bash

# ==============================================================================
# VAAPI driver Intall Script for Arch Linux
# ==============================================================================
# This script automates the installation of Video Acceleration API drivers
# for use with Hyprland on Arch Linux.
#
# Author: https://github.com/elbrodino following https://github.com/PinheiroCosta
# recommendations
#
# ==============================================================================

# --- Listing all GPU to check for, with their plugin name ---
#

# Driver packages per manufacturer
declare -A GPU_list
GPU_list[Intel]="intel-media-driver"
GPU_list[AMD]="libva-mesa-driver mesa-vdpau"
GPU_list[NVIDIA]="libva-nvidia-driver"
declare -A VULKAN_DRIVER_PACKAGE

# --- GPU Detection --
echo "Checking GPU ..."

for i in ${!GPU_list[@]}; do
  if lspci | grep -i "Display controller: $i" >/dev/null ||
    lspci | grep -i "VGA compatible controller: $i" >/dev/null; then
    VULKAN_DRIVER_PACKAGE+=${GPU_list[$i]}
  fi
done

if [[ -z $VULKAN_DRIVER_PACKAGE ]]; then
  echo "No GPU detected"
  exit 1

# --- Checking installed package ---
# Building a list of missing packages
else
  declare -A ListToInstall
  for i in "${VULKAN_DRIVER_PACKAGE[@]}"; do
    echo "Checking if package is already installed: $i"
    if ! (pacman -Qi $i) >/dev/null ; then
      echo "Missing VAAPI Driver: $i"
      ListToInstall+="$i "
    else
      echo "Great, $i package already installed!"
    fi
  done

  if ! [[ -z ${ListToInstall} ]]; then #not empty
    echo "Installing missing packages..."
    sudo pacman -S --needed --noconfirm ${ListToInstall[@]}
  fi
fi
