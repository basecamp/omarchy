#!/bin/bash

if ! command -v pactree &>/dev/null; then
    yay -S --noconfirm --needed pacman-contrib
fi

if pacman -Qi hyprutils-git &> /dev/null; then
    if pacman -Qi hyprsunset-git &> /dev/null; then
        # basically leftovers from other Hyprland installations lihe JaCoolit that can mess things up
        yay -R --noconfirm hyprsunset-git
        yay -S --noconfirm hyprutils hyprsunset
fi

yay -S --noconfirm --needed \
    hyprland hyprshot hyprpicker hyprlock hypridle polkit-gnome hyprland-qtutils \
    wofi waybar mako swaybg \
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
