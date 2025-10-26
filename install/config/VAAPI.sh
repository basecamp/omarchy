#!/bin/bash

# ==============================================================================
# Hyprland Vulkan Setup Script for Arch Linux
# ==============================================================================
# This script automates the installation of VULKAN drivers
# for use with Hyprland on Arch Linux, following the official Hyprland wiki.
#
# Author: https://github.com/elbrodino inspired by Kn0ax
#
# ==============================================================================

# --- Listing all GPU to check for, with their plugin name ---
# we're assuming they start with 'vulkan-'
#

# Driver packages per manufacturer
declare -A GPU_list
GPU_list[Intel]="intel-media-driver"
GPU_list[AMD]="libva-mesa-driver mesa-vdpau"
GPU_list[NVIDIA]="libva-nvidia-driver"
declare -A VULKAN_DRIVER_PACKAGE

# --- GPU Detection --
echo "Checking GPU ..."

{
for i in "${!GPU_list[@]}"; do
  if lspci | grep -i "Display controller: $i" >/dev/null ||
    lspci | grep -i "VGA compatible controller: $i" >/dev/null; then
    VULKAN_DRIVER_PACKAGE+="$i"
  fi
done
  echo "Detected GPU: ${VULKAN_DRIVER_PACKAGE[@]}"
}

# --- Install package ---
if [[ -v VULKAN_DRIVER_PACKAGE ]]; then

  # checking if the appropriate parckage is installed
  for i in "${VULKAN_DRIVER_PACKAGE[@]}"; do
    echo "Checking if package is already installed: ${GPU_list["Intel"]}"
    if !(pacman -Qi ${VULKAN_DRIVER_PACKAGE[$i]} ) >/dev/null; then
      echo "Missing Vulkan Drivers, installing ${GPU_list[ ${VULKAN_DRIVER_PACKAGE[$i]} ]}"
      sudo pacman -S --needed --noconfirm ${GPU_list[${VULKAN_DRIVER_PACKAGE[$i]}]}
    else
      echo "Great, Vulkan package installed!"
    fi
  done
fi
