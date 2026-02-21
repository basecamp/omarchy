echo "Hide fcitx5 tray icon from waybar"

mkdir -p ~/.config/fcitx5/addon
cp $OMARCHY_PATH/config/fcitx5/addon/notificationitem.conf ~/.config/fcitx5/addon/
