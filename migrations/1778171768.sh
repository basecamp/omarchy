echo "Run SwayOSD as a supervised session service"

SERVICE=swayosd-server.service

if omarchy-cmd-missing swayosd-server; then
  omarchy-pkg-add swayosd
fi

sudo systemctl enable --now swayosd-libinput-backend.service

mkdir -p ~/.config/systemd/user
cp "$OMARCHY_PATH/config/systemd/user/$SERVICE" "$HOME/.config/systemd/user/$SERVICE"

pkill -x swayosd-server || true

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE"
