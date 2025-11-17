pkill elephant
elephant service enable
systemctl --user start elephant.service

mkdir -p ~/.config/autostart/
cp $OMARCHY_PATH/autostart/walker.desktop ~/.config/autostart/
