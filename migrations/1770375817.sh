echo "Ensure walker service is restarted if it's killed or crashes"

mkdir -p ~/.config/systemd/user/app-walker@autostart.service.d/
cp $OMARCHY_PATH/default/walker/restart.conf ~/.config/systemd/user/app-walker@autostart.service.d/restart.conf
systemctl --user daemon-reload

