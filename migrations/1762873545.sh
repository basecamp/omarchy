pkill elephant
elephant service enable
systemctl --user start elephant.service

pkill walker
mkdir -p ~/.config/autostart/
cp $OMARCHY_PATH/autostart/walker.desktop ~/.config/autostart/
systemctl --user start app-walker@autostart.service
