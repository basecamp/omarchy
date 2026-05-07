sudo systemctl enable --now swayosd-libinput-backend.service

systemctl --user daemon-reload
systemctl --user enable --now swayosd-server.service
