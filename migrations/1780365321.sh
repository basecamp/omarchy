echo "Use GNOME file picker portal for previews in Open/Save dialogs"

omarchy-pkg-add xdg-desktop-portal-gnome

omarchy-refresh-config xdg-desktop-portal/hyprland-portals.conf

systemctl --user restart xdg-desktop-portal
