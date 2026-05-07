echo "Run SwayOSD as a supervised session service"

SERVICE=swayosd-server.service

mkdir -p ~/.config/systemd/user
cp "$OMARCHY_PATH/config/systemd/user/$SERVICE" ~/.config/systemd/user/$SERVICE

if [[ -f ~/.config/hypr/autostart.conf ]]; then
  sed -i '/^exec-once = uwsm-app -- swayosd-server$/d' ~/.config/hypr/autostart.conf
fi

pkill -x swayosd-server || true

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE"
