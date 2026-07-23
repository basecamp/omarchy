UPDATEDB_CONF_PATH="${OMARCHY_UPDATEDB_CONF_PATH:-/etc/updatedb.conf}"

echo "Configuring locate to skip Btrfs snapshots and index Btrfs subvolumes"

[[ -f $UPDATEDB_CONF_PATH ]] || exit 0

# Btrfs subvolume mounts (like /home) look like bind mounts, so pruning
# bind mounts leaves them out of the index entirely.
if grep -qE '^PRUNE_BIND_MOUNTS[[:space:]]*=' "$UPDATEDB_CONF_PATH"; then
  sed -i -E 's|^PRUNE_BIND_MOUNTS[[:space:]]*=.*|PRUNE_BIND_MOUNTS = "no"|' "$UPDATEDB_CONF_PATH"
else
  printf '%s\n' 'PRUNE_BIND_MOUNTS = "no"' >>"$UPDATEDB_CONF_PATH"
fi

# Snapper snapshots are nested subvolumes reached by plain directory
# traversal, so without this updatedb indexes the system once per snapshot.
if ! grep -E '^PRUNEPATHS[[:space:]]*=' "$UPDATEDB_CONF_PATH" | grep -qF '/.snapshots'; then
  if grep -qE '^PRUNEPATHS[[:space:]]*=[[:space:]]*"' "$UPDATEDB_CONF_PATH"; then
    sed -i -E 's|^(PRUNEPATHS[[:space:]]*=[[:space:]]*")|\1/.snapshots |' "$UPDATEDB_CONF_PATH"
  else
    printf '%s\n' 'PRUNEPATHS = "/.snapshots"' >>"$UPDATEDB_CONF_PATH"
  fi
fi
