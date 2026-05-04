# Setup passwordless sudo for camera device access control.
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/fuser -k /dev/video*" | sudo tee /etc/sudoers.d/camera-toggle
sudo chmod 440 /etc/sudoers.d/camera-toggle
