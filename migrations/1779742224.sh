echo "Gate bluetooth pairing agent on active bluetooth service"

mkdir -p "$HOME/.config/systemd/user/"
cp "$OMARCHY_PATH/config/systemd/user/bt-agent.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload

if systemctl --user is-enabled --quiet bt-agent.service; then
  systemctl --user reset-failed bt-agent.service 2>/dev/null || true
fi
