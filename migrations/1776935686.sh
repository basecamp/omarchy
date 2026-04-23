echo "Recover the internal monitor at login when no external display is connected"

SERVICE=omarchy-recover-internal-monitor.service

mkdir -p ~/.config/systemd/user
cp $OMARCHY_PATH/config/systemd/user/$SERVICE ~/.config/systemd/user/$SERVICE

systemctl --user daemon-reload
systemctl --user enable $SERVICE
