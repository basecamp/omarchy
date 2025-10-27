#!/usr/bin/env bash

sudo cp -f ~/.local/share/omarchy/default/networkmanager/omarchy_networkmanager.conf /etc/NetworkManager/conf.d/omarchy_networkmanager.conf

sudo systemctl mask --now wpa_supplicant.service
sudo systemctl disable --now systemd-networkd.socket
sudo systemctl disable --now systemd-networkd-varlink.socket
sudo systemctl disable --now systemd-networkd.service
sudo systemctl restart systemd-resolved.service
sudo systemctl enable --now NetworkManager.service
