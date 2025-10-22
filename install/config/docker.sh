sudo usermod -aG docker ${USER}
sudo systemctl restart systemd-resolved
sudo systemctl enable docker
sudo systemctl daemon-reload
