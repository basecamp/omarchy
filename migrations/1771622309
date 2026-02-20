echo "Fix locate not indexing home on Btrfs"
sudo sed -i 's/PRUNE_BIND_MOUNTS.*=.*/PRUNE_BIND_MOUNTS = "no"/' /etc/updatedb.conf
sudo updatedb
