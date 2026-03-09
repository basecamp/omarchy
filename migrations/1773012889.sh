echo "Install system-sleep hook to unmount FUSE before suspend/hibernate"

sudo mkdir -p /usr/lib/systemd/system-sleep
sudo install -m 0755 -o root -g root "$OMARCHY_PATH/default/systemd/system-sleep/unmount-fuse" /usr/lib/systemd/system-sleep/
