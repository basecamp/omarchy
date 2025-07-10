yay -S --noconfirm --needed polkit-gnome
systemctl --user stop hyprpolkitagent
systemctl --user disable hyprpolkitagent
yay -Rns --noconfirm hyprpolkitagent
