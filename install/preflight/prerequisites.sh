#!/bin/bash

if [ ! -f /etc/os-release ]; then
  echo "$(tput setaf 1)Error: Unable to determine OS. /etc/os-release file not found."
  echo "Installation stopped."
  exit 1
fi

. /etc/os-release

# Check if running on x86
ARCH=$(uname -m)

if [ "$ARCH" = "aarch64" ]; then
  echo "$(tput setaf 1)Error: aarch64 is not supported."
  echo "Hyprland, a required dependency, does not support this architecture."
  echo "Installation stopped."
  exit 1
fi

if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "i686" ]; then
  echo "$(tput setaf 1)Error: Unsupported architecture: $ARCH"
  echo "This installation is only supported on x86_64 or i686."
  echo "Installation stopped."
  exit 1
fi

# Check if running on Arch Linux
if [ "$ID" != "arch" ]; then
  echo "$(tput setaf 1)Error: OS requirement not met"
  echo "You are currently running: $ID"
  echo "OS required: Arch Linux"
  echo "Installation stopped."
  exit 1
fi
