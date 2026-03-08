echo "Install system-sleep hook to unmount FUSE before suspend/hibernate"

sudo mkdir -p /usr/lib/systemd/system-sleep
sudo cp -p "$OMARCHY_PATH/default/systemd/system-sleep/unmount-fuse" /usr/lib/systemd/system-sleep/
