sudo mkdir -p /etc/systemd/system.conf.d
sudo cp "$OMARCHY_PATH/default/systemd/faster-shutdown.conf" /etc/systemd/system.conf.d/10-faster-shutdown.conf
sudo systemctl daemon-reload
