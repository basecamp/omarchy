echo "Change behaviour of XF86PowerOff button to show omarchy system menu insead of shutting down immediately"

source $OMARCHY_PATH/install/config/ignore-power-button.sh
setsid systemd-inhibit --what=handle-power-key --why="Temporary disable power button before restart" sleep infinity &

