# Install system-sleep hook to prevent GPU suspend hang (omarchy#5277)
sudo mkdir -p /etc/systemd/system-sleep
sudo install -m 0755 -o root -g root "$OMARCHY_PATH/default/systemd/system-sleep/nvidia-hyprlock" /etc/systemd/system-sleep/
