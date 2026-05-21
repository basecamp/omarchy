echo "Install sleep lock service"

mkdir -p ~/.config/systemd/user/
cp "$OMARCHY_PATH/config/systemd/user/omarchy-sleep-lock.service" ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user reset-failed omarchy-sleep-lock.service 2>/dev/null || true
systemctl --user enable --now omarchy-sleep-lock.service
