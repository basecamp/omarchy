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

declare -A GPU_list
GPU_list[Intel]="intel"
GPU_list[AMD]="radeon"
GPU_list[Apple]="asahi"
GPU_list[NVIDIA]="nouveau"
declare -A VULKAN_DRIVER_PACKAGE

# --- GPU Detection --
echo "Checking GPU ..."

for i in "${!GPU_list[@]}"; do
  if lspci | grep -i "Display controller: $i" >/dev/null ||
    lspci | grep -i "VGA compatible controller: $i" >/dev/null; then
    VULKAN_DRIVER_PACKAGE+="vulkan-${GPU_list[$i]} "
  fi
done

# --- Install package ---
if [[ -v VULKAN_DRIVER_PACKAGE ]]; then
  echo "Detected display : ${VULKAN_DRIVER_PACKAGE[@]}"

  # checking if the appropriate parckage is installed
  for i in "${VULKAN_DRIVER_PACKAGE[@]}"; do
    echo "Checking if package isalready installed: $i"
    if !(pacman -Qi $i ) >/dev/null; then
      echo "Missing Vulkan Drivers, installing ${VULKAN_DRIVER_PACKAGE}"
      sudo pacman -S --needed --noconfirm ${VULKAN_DRIVER_PACKAGE[@]}
    else
      echo "Great, Vulkan package installed!"
    fi
  done
   "Next, installing Zed!"
fi
