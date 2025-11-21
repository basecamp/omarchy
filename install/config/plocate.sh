# Disable plocate database updates on boot to avoid I/O load during startup. Updates still run on daily schedule.
sudo mkdir -p /etc/systemd/system/plocate-updatedb.timer.d
echo -e "[Timer]\nPersistent=false" | sudo tee /etc/systemd/system/plocate-updatedb.timer.d/override.conf > /dev/null
sudo systemctl daemon-reload
