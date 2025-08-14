echo "Change behaviour of XF86PowerOff button to show omarchy system menu insead of shutting down immediately"

source $OMARCHY_PATH/install/config/ignore-power-button.sh
# Whole hyprland got killed when I try to use `systemctl restart systemd-logind` so here is a workaround to handle it 
systemd-inhibit --what=handle-power-key --why="Temporary disable power button before restart" sleep infinity &