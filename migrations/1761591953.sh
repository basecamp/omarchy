#!/usr/bin/env bash
echo "Mask wpa_supplicant and disable systemd-networkd, enable NetworkManager"

sudo systemctl mask --now wpa_supplicant.service
sudo systemctl disable --now systemd-networkd.socket
sudo systemctl disable --now systemd-networkd-varlink.socket
sudo systemctl disable --now systemd-networkd.service
sudo systemctl restart systemd-resolved.service
sudo systemctl enable --now NetworkManager.service
