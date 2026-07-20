echo "Allow plocate to index Btrfs subvolumes (including home)"

if grep -q '^PRUNE_BIND_MOUNTS.*=.*"yes"' /etc/updatedb.conf; then
  sudo sed -i 's/^PRUNE_BIND_MOUNTS.*=.*"yes"/PRUNE_BIND_MOUNTS = "no"/' /etc/updatedb.conf
fi
