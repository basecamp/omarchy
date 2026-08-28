echo "Enable the inert Omarchy plugin host"

systemctl --user daemon-reload
systemctl --user enable omarchy-plugin-host.service

if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-plugin-host.service
fi
