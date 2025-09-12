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

#VULKAN_DRIVER_PACKAGE=""

# --- Listing all GPU to check for, with their plugin name
# we're assuming they start with 'vulkan-'
declare -A GPU_list
GPU_list[Intel]="intel"
GPU_list[AMD]="radeon"
GPU_list[Apple]="asahi"
GPU_list[NVIDIA]="nouveau"

# --- GPU Detection --
for i in "${!GPU_list[@]}"; do
    echo "Detecting GPU: $i"

    if lspci | grep -i "Display controller: $i"||
       lspci | grep -i "VGA compatible controller: $i" ; then
           echo "    Success, $i GPU detected"
        VULKAN_DRIVER_PACKAGE+="vulkan-${GPU_list[$i]}"
    else
        echo "    $i GPU not present"
    fi
done

echo "Listing VULKAN_DRIVER_PACKAGE"
for i in "$VULKAN_DRIVER_PACKAGE"; do
  echo "$i"
done

# Install package
if [[ -v VULKAN_DRIVER_PACKAGE ]]; then
    echo -n "GPU detected, installing" ${VULKAN_DRIVER_PACKAGE[@]} "[y/n]: "
    read -r ans

    if [[ $ans == "y" ]] ; then
        sudo pacman -S --needed --noconfirm "$VULKAN_DRIVER_PACKAGE"
        echo "Vulkan driver installed"
    else
        echo "aborting"
        exit 1
    fi
else
    echo "No GPU detected, aborting vulkan plugin installation."
    exit 1
fi
