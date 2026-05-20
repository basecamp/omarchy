# Docker config files ship via omarchy-settings. This script only handles
# runtime side: reload systemd-resolved so the new drop-in takes effect and
# add the current user to the docker group. docker.socket enable lives in
# install/config/enable-services.sh.
sudo systemctl restart systemd-resolved
sudo usermod -aG docker ${USER}
sudo systemctl daemon-reload
