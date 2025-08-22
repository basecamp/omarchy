#!/usr/bin/env bash

# Start logging a copy of everything sent to STDOUT and STDERR
mkdir -p ~/.local/state/omarchy/logs/
exec &> >(tee -a ~/.local/state/omarchy/logs/installation.log)

echo "--- System state before installation ---"
sudo pacman -S --noconfirm fastfetch
fastfetch

echo -e "\n--- System logs (journalctl / current boot) ---"
journalctl -b --no-pager

echo -e "\n--- Pacman packages (before installation) ---"
echo "Total packages installed: $(pacman -Q | wc -l)"
pacman -Q
