echo "Route file chooser portal requests to Nautilus"

source "$OMARCHY_PATH/install/user/xdg-desktop-portal.sh"

systemctl --user try-restart xdg-desktop-portal.service
