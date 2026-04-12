# Install system-sleep hook to prevent GPU suspend hang (omarchy#5277)
sudo mkdir -p /usr/lib/systemd/system-sleep
sudo install -m 0755 -o root -g root "$OMARCHY_PATH/default/systemd/system-sleep/nvidia-hyprlock" /usr/lib/systemd/system-sleep/
