# Docker config files (daemon.json, resolved drop-in, no-block-boot drop-in)
# ship via omarchy-settings. This script only handles the runtime side:
# - reload systemd-resolved so the new drop-in takes effect
# - add the current user to the docker group
# - enable docker.socket and reload systemd unit files

sudo systemctl restart systemd-resolved
sudo systemctl enable docker.socket
sudo usermod -aG docker ${USER}
sudo systemctl daemon-reload
