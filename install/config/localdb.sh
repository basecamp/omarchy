# Ensure /home is indexed on Btrfs (subvolumes look like bind mounts)
sudo sed -i 's/PRUNE_BIND_MOUNTS.*=.*/PRUNE_BIND_MOUNTS = "no"/' /etc/updatedb.conf
sudo updatedb
