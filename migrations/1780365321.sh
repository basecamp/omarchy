echo "Use GNOME file picker portal for previews in Open/Save dialogs"

omarchy-pkg-add xdg-desktop-portal-gnome

mkdir -p ~/.config/xdg-desktop-portal
cp $OMARCHY_PATH/config/xdg-desktop-portal/hyprland-portals.conf ~/.config/xdg-desktop-portal/

systemctl --user restart xdg-desktop-portal
