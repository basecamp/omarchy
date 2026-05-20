sudo systemctl restart systemd-resolved
sudo usermod -aG docker ${USER}
sudo systemctl daemon-reload
