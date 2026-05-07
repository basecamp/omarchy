mkdir -p ~/.config/systemd/user
cp "$OMARCHY_PATH/config/systemd/user/swayosd-server.service" ~/.config/systemd/user/swayosd-server.service

systemctl --user daemon-reload
systemctl --user enable --now swayosd-server.service
