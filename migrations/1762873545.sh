echo "Switch Elephant to run as a systemd service and walker to be autostarted on login"

pkill elephant
elephant service enable
systemctl --user start elephant.service

pkill walker
mkdir -p ~/.config/autostart/
cp $OMARCHY_PATH/default/walker/walker.desktop ~/.config/autostart/
setsid walker --gapplication-service &
