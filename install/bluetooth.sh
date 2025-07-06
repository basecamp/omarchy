# Install bluetooth controls
sudo dnf install -y blueberry

# Turn on bluetooth by default
sudo systemctl enable --now bluetooth.service
