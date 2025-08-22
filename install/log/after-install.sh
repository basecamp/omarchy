#!/usr/bin/env bash

echo -e "\n--- Pacman packages (after installation) ---"
echo "Total packages installed: $(pacman -Q | wc -l)"
pacman -Q
